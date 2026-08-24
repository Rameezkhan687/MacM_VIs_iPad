import Foundation

public struct ComparativeModeler: Sendable {
    public init() {}

    /// Builds a lightweight backbone trace across numbered residue gaps. This is
    /// intended for interactive hypothesis generation, not final refinement.
    public func fillingBackboneLoops(in structure: MolecularStructure, maximumGap: Int = 25) -> MolecularStructure {
        var atoms = structure.atoms
        let chainIDs = Set(structure.atoms.map(\.chainID))
        for chainID in chainIDs {
            let anchors = structure.atoms
                .filter { $0.chainID == chainID && $0.name.uppercased() == "CA" }
                .sorted { $0.residueNumber < $1.residueNumber }
            for pair in zip(anchors, anchors.dropFirst()) {
                let gap = pair.1.residueNumber - pair.0.residueNumber
                guard gap > 1, gap - 1 <= maximumGap else { continue }
                let delta = pair.1.position - pair.0.position
                let length = max(0.001, delta.length)
                let direction = delta / length
                let normal = abs(direction.y) < 0.9
                    ? normalized(cross(direction, Vector3(x: 0, y: 1, z: 0)))
                    : normalized(cross(direction, Vector3(x: 1, y: 0, z: 0)))
                for step in 1..<gap {
                    let fraction = Float(step) / Float(gap)
                    let ca = pair.0.position + scaled(delta, fraction)
                    let residueNumber = pair.0.residueNumber + step
                    let positions: [(String, String, Vector3)] = [
                        ("N", "N", ca - scaled(direction, 1.2)),
                        ("CA", "C", ca),
                        ("C", "C", ca + scaled(direction, 1.2)),
                        ("O", "O", ca + scaled(direction, 1.2) + scaled(normal, 0.75))
                    ]
                    for entry in positions {
                        atoms.append(Atom(
                            id: atoms.count, serial: atoms.count + 1,
                            name: entry.0, element: entry.1,
                            residueName: "UNK", residueNumber: residueNumber,
                            chainID: chainID, position: entry.2, bFactor: 50
                        ))
                    }
                }
            }
        }
        guard atoms.count != structure.atoms.count else { return structure }
        return rebuilt(structure, atoms: atoms, name: "\(structure.name) · loops modeled")
    }

    /// Copies atoms absent from the target after the caller has structurally
    /// aligned a template. Existing coordinates always win.
    public func completing(_ target: MolecularStructure, fromAlignedTemplate template: MolecularStructure) -> MolecularStructure {
        var atoms = target.atoms
        let existing = Set(target.atoms.map(atomKey))
        for atom in template.atoms where !existing.contains(atomKey(atom)) {
            atoms.append(Atom(
                id: atoms.count, serial: atoms.count + 1, name: atom.name,
                element: atom.element, residueName: atom.residueName,
                residueNumber: atom.residueNumber, chainID: atom.chainID,
                position: atom.position, occupancy: atom.occupancy,
                bFactor: atom.bFactor, isHetero: atom.isHetero,
                partialCharge: atom.partialCharge
            ))
        }
        guard atoms.count != target.atoms.count else { return target }
        return rebuilt(target, atoms: atoms, name: "\(target.name) · completed from template")
    }

    private func rebuilt(_ source: MolecularStructure, atoms: [Atom], name: String) -> MolecularStructure {
        let normalizedAtoms = atoms.enumerated().map { index, atom in
            Atom(
                id: index, serial: index + 1, name: atom.name, element: atom.element,
                residueName: atom.residueName, residueNumber: atom.residueNumber,
                chainID: atom.chainID, position: atom.position, occupancy: atom.occupancy,
                bFactor: atom.bFactor, isHetero: atom.isHetero, partialCharge: atom.partialCharge
            )
        }
        return MolecularStructure(
            name: name, atoms: normalizedAtoms, bonds: BondInference.infer(atoms: normalizedAtoms),
            secondaryStructure: source.secondaryStructure
        )
    }

    private func atomKey(_ atom: Atom) -> String {
        "\(atom.chainID)|\(atom.residueNumber)|\(atom.name.uppercased())"
    }

    private func scaled(_ value: Vector3, _ scalar: Float) -> Vector3 {
        Vector3(x: value.x * scalar, y: value.y * scalar, z: value.z * scalar)
    }

    private func cross(_ first: Vector3, _ second: Vector3) -> Vector3 {
        Vector3(
            x: first.y * second.z - first.z * second.y,
            y: first.z * second.x - first.x * second.z,
            z: first.x * second.y - first.y * second.x
        )
    }

    private func normalized(_ value: Vector3) -> Vector3 {
        value / max(0.001, value.length)
    }
}
