import Foundation

public struct MolecularEditor: Sendable {
    public init() {}

    public func addingAtom(
        to structure: MolecularStructure,
        element: String,
        position: Vector3,
        residueName: String = "LIG",
        residueNumber: Int = 1,
        chainID: String = "L"
    ) -> MolecularStructure {
        var copy = structure
        let id = (copy.atoms.map(\.id).max() ?? -1) + 1
        let serial = (copy.atoms.map(\.serial).max() ?? 0) + 1
        copy.atoms.append(Atom(
            id: id,
            serial: serial,
            name: "\(ElementTable.normalized(element))\(serial)",
            element: element,
            residueName: residueName.uppercased(),
            residueNumber: residueNumber,
            chainID: chainID,
            position: position,
            isHetero: true
        ))
        return copy
    }

    public func deletingAtoms(_ ids: Set<Int>, from structure: MolecularStructure) -> MolecularStructure {
        guard !ids.isEmpty else { return structure }
        var copy = structure
        let remaining = structure.atoms.filter { !ids.contains($0.id) }
        let idMap = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element.id, $0.offset) })
        copy.atoms = remaining.enumerated().map { index, atom in copiedAtom(atom, id: index, serial: index + 1) }
        copy.bonds = structure.bonds.compactMap { bond in
            guard let first = idMap[bond.atom1], let second = idMap[bond.atom2] else { return nil }
            return Bond(atom1: first, atom2: second, order: bond.order)
        }
        copy.alternateConformations = []
        copy.biologicalAssemblies = []
        return copy
    }

    public func addingBond(_ first: Int, _ second: Int, order: Int = 1, to structure: MolecularStructure) -> MolecularStructure {
        guard first != second,
              structure.atoms.contains(where: { $0.id == first }),
              structure.atoms.contains(where: { $0.id == second }) else { return structure }
        var copy = structure
        let bond = Bond(atom1: first, atom2: second, order: min(3, max(1, order)))
        if !copy.bonds.contains(bond) { copy.bonds.append(bond) }
        return copy
    }

    public func deletingBond(_ first: Int, _ second: Int, from structure: MolecularStructure) -> MolecularStructure {
        var copy = structure
        let target = Bond(atom1: first, atom2: second)
        copy.bonds.removeAll { $0.atom1 == target.atom1 && $0.atom2 == target.atom2 }
        return copy
    }

    public func mutatingResidue(
        chainID: String,
        residueNumber: Int,
        to newName: String,
        in structure: MolecularStructure
    ) -> MolecularStructure {
        var copy = structure
        copy.atoms = copy.atoms.map { atom in
            guard atom.chainID.caseInsensitiveCompare(chainID) == .orderedSame,
                  atom.residueNumber == residueNumber else { return atom }
            return copiedAtom(atom, residueName: newName.uppercased())
        }
        return copy
    }

    public func renamingChain(_ oldID: String, to newID: String, in structure: MolecularStructure) -> MolecularStructure {
        var copy = structure
        copy.atoms = copy.atoms.map { atom in
            atom.chainID.caseInsensitiveCompare(oldID) == .orderedSame ? copiedAtom(atom, chainID: newID) : atom
        }
        copy.secondaryStructure = copy.secondaryStructure.map { segment in
            segment.chainID.caseInsensitiveCompare(oldID) == .orderedSame
                ? SecondaryStructureSegment(kind: segment.kind, chainID: newID, startResidue: segment.startResidue, endResidue: segment.endResidue)
                : segment
        }
        return copy
    }

    public func addingHydrogens(to structure: MolecularStructure) -> MolecularStructure {
        var copy = structure
        let center = structure.center
        let bondedIDs = Set(structure.bonds.flatMap { [$0.atom1, $0.atom2] })
        for atom in structure.atoms.prefix(50_000) {
            let element = ElementTable.normalized(atom.element)
            guard ["N", "O", "S"].contains(element) || (element == "C" && !bondedIDs.contains(atom.id)) else { continue }
            let outward = atom.position - center
            let length = max(0.001, outward.length)
            let direction = outward / length
            let id = copy.atoms.count
            copy.atoms.append(Atom(
                id: id,
                serial: id + 1,
                name: "H\(id + 1)",
                element: "H",
                residueName: atom.residueName,
                residueNumber: atom.residueNumber,
                chainID: atom.chainID,
                position: atom.position + Vector3(x: direction.x, y: direction.y, z: direction.z),
                isHetero: atom.isHetero,
                partialCharge: 0.1
            ))
            copy.bonds.append(Bond(atom1: atom.id, atom2: id))
        }
        return copy
    }

    public func assigningSimpleCharges(to structure: MolecularStructure) -> MolecularStructure {
        var copy = structure
        for index in copy.atoms.indices {
            copy.atoms[index].partialCharge = switch ElementTable.normalized(copy.atoms[index].element) {
            case "O": -0.5
            case "N": -0.3
            case "S": -0.2
            case "P": 0.5
            case "H": 0.2
            default: 0
            }
        }
        return copy
    }

    public func dockPrepared(_ structure: MolecularStructure) -> MolecularStructure {
        let waters = Set(structure.atoms.filter { ["HOH", "WAT", "H2O"].contains($0.residueName.uppercased()) }.map(\.id))
        return assigningSimpleCharges(to: addingHydrogens(to: deletingAtoms(waters, from: structure)))
    }

    public func minimized(_ structure: MolecularStructure, iterations: Int = 30, step: Float = 0.025) -> MolecularStructure {
        var copy = structure
        guard !copy.atoms.isEmpty else { return copy }
        let atomIndex = Dictionary(uniqueKeysWithValues: copy.atoms.enumerated().map { ($0.element.id, $0.offset) })
        for _ in 0..<min(200, max(1, iterations)) {
            var displacement = [Vector3](repeating: .zero, count: copy.atoms.count)
            for bond in copy.bonds {
                guard let first = atomIndex[bond.atom1], let second = atomIndex[bond.atom2] else { continue }
                let delta = copy.atoms[second].position - copy.atoms[first].position
                let distance = max(0.001, delta.length)
                let target = ElementTable.covalentRadius(for: copy.atoms[first].element) + ElementTable.covalentRadius(for: copy.atoms[second].element)
                let force = (distance - target) * step
                let direction = delta / distance
                let change = Vector3(x: direction.x * force, y: direction.y * force, z: direction.z * force)
                displacement[first] = displacement[first] + change
                displacement[second] = displacement[second] - change
            }
            for index in copy.atoms.indices { copy.atoms[index].position = copy.atoms[index].position + displacement[index] }
        }
        return copy
    }

    public func rotatedAroundBond(
        _ firstID: Int,
        _ secondID: Int,
        degrees: Float,
        in structure: MolecularStructure
    ) -> MolecularStructure {
        guard let first = structure.atoms.first(where: { $0.id == firstID }),
              let second = structure.atoms.first(where: { $0.id == secondID }) else { return structure }
        var adjacency: [Int: [Int]] = [:]
        for bond in structure.bonds {
            adjacency[bond.atom1, default: []].append(bond.atom2)
            adjacency[bond.atom2, default: []].append(bond.atom1)
        }
        var rotating = Set<Int>(), queue = [secondID]
        while let current = queue.popLast() {
            guard current != firstID else { continue }
            guard rotating.insert(current).inserted else { continue }
            for neighbor in adjacency[current] ?? [] where neighbor != firstID { queue.append(neighbor) }
        }
        let axisVector = second.position - first.position
        let length = max(0.001, axisVector.length)
        let axis = axisVector / length
        let angle = degrees * .pi / 180
        var copy = structure
        for index in copy.atoms.indices where rotating.contains(copy.atoms[index].id) {
            copy.atoms[index].position = rotate(copy.atoms[index].position, around: first.position, axis: axis, angle: angle)
        }
        return copy
    }

    public func translated(_ ids: Set<Int>, by offset: Vector3, in structure: MolecularStructure) -> MolecularStructure {
        var copy = structure
        for index in copy.atoms.indices where ids.contains(copy.atoms[index].id) {
            copy.atoms[index].position = copy.atoms[index].position + offset
        }
        return copy
    }

    private func rotate(_ point: Vector3, around origin: Vector3, axis: Vector3, angle: Float) -> Vector3 {
        let p = point - origin
        let cosine = cos(angle), sine = sin(angle)
        let dot = axis.x * p.x + axis.y * p.y + axis.z * p.z
        let cross = Vector3(
            x: axis.y * p.z - axis.z * p.y,
            y: axis.z * p.x - axis.x * p.z,
            z: axis.x * p.y - axis.y * p.x
        )
        return origin + Vector3(
            x: p.x * cosine + cross.x * sine + axis.x * dot * (1 - cosine),
            y: p.y * cosine + cross.y * sine + axis.y * dot * (1 - cosine),
            z: p.z * cosine + cross.z * sine + axis.z * dot * (1 - cosine)
        )
    }

    private func copiedAtom(
        _ atom: Atom,
        id: Int? = nil,
        serial: Int? = nil,
        residueName: String? = nil,
        chainID: String? = nil
    ) -> Atom {
        Atom(
            id: id ?? atom.id,
            serial: serial ?? atom.serial,
            name: atom.name,
            element: atom.element,
            residueName: residueName ?? atom.residueName,
            residueNumber: atom.residueNumber,
            chainID: chainID ?? atom.chainID,
            position: atom.position,
            occupancy: atom.occupancy,
            bFactor: atom.bFactor,
            isHetero: atom.isHetero,
            partialCharge: atom.partialCharge
        )
    }
}
