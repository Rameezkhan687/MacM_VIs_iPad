import Foundation

public struct SDFParser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "Molecule") throws -> MolecularStructure {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidStructure("The SDF/MOL file is not readable text.")
        }
        return try parse(text, name: name)
    }

    public func parse(_ text: String, name: String = "Molecule") throws -> MolecularStructure {
        let record = text.components(separatedBy: "$$$$").first ?? text
        let lines = record.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 4 else { throw MolecularError.invalidStructure("The MOL header is incomplete.") }
        let counts = fields(lines[3])
        guard counts.count >= 2, let atomCount = Int(counts[0]), let bondCount = Int(counts[1]),
              atomCount > 0, lines.count >= 4 + atomCount + bondCount else {
            throw MolecularError.invalidStructure("The MOL counts line is invalid.")
        }

        var atoms: [Atom] = []
        for index in 0..<atomCount {
            let values = fields(lines[4 + index])
            guard values.count >= 4,
                  let x = Float(values[0]), let y = Float(values[1]), let z = Float(values[2]) else { continue }
            let element = values[3]
            atoms.append(Atom(
                id: atoms.count,
                serial: atoms.count + 1,
                name: "\(element)\(atoms.count + 1)",
                element: element,
                residueName: "LIG",
                residueNumber: 1,
                chainID: "L",
                position: Vector3(x: x, y: y, z: z),
                isHetero: true
            ))
        }
        guard atoms.count == atomCount else { throw MolecularError.invalidStructure("Some MOL atom rows are invalid.") }

        var bonds: [Bond] = []
        for index in 0..<bondCount {
            let values = fields(lines[4 + atomCount + index])
            guard values.count >= 3, let first = Int(values[0]), let second = Int(values[1]), let order = Int(values[2]),
                  (1...atomCount).contains(first), (1...atomCount).contains(second) else { continue }
            bonds.append(Bond(atom1: first - 1, atom2: second - 1, order: min(max(1, order), 3)))
        }
        return MolecularStructure(name: lines.first?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? name, atoms: atoms, bonds: bonds)
    }

    private func fields(_ line: String) -> [String] {
        line.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

public struct MOL2Parser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "Molecule") throws -> MolecularStructure {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidStructure("The MOL2 file is not readable text.")
        }
        return try parse(text, name: name)
    }

    public func parse(_ text: String, name: String = "Molecule") throws -> MolecularStructure {
        enum Section { case none, molecule, atom, bond }
        var section = Section.none
        var moleculeName = name
        var expectsName = false
        var atoms: [Atom] = []
        var fileIDToAtomID: [Int: Int] = [:]
        var bonds: [Bond] = []

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.uppercased() == "@<TRIPOS>MOLECULE" { section = .molecule; expectsName = true; continue }
            if line.uppercased() == "@<TRIPOS>ATOM" { section = .atom; continue }
            if line.uppercased() == "@<TRIPOS>BOND" { section = .bond; continue }
            if line.hasPrefix("@<TRIPOS>") { section = .none; continue }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if section == .molecule, expectsName {
                moleculeName = line
                expectsName = false
            } else if section == .atom {
                let values = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard values.count >= 6, let fileID = Int(values[0]),
                      let x = Float(values[2]), let y = Float(values[3]), let z = Float(values[4]) else { continue }
                let element = String(values[5].split(separator: ".").first ?? "C").replacingOccurrences(of: "ar", with: "C")
                let id = atoms.count
                fileIDToAtomID[fileID] = id
                atoms.append(Atom(
                    id: id,
                    serial: fileID,
                    name: values[1],
                    element: element,
                    residueName: values.count > 7 ? values[7] : "LIG",
                    residueNumber: values.count > 6 ? Int(values[6]) ?? 1 : 1,
                    chainID: "L",
                    position: Vector3(x: x, y: y, z: z),
                    isHetero: true
                ))
            } else if section == .bond {
                let values = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard values.count >= 4, let source = Int(values[1]), let target = Int(values[2]),
                      let first = fileIDToAtomID[source], let second = fileIDToAtomID[target] else { continue }
                let order = Int(values[3]) ?? (values[3].lowercased() == "ar" ? 2 : 1)
                bonds.append(Bond(atom1: first, atom2: second, order: order))
            }
        }
        guard !atoms.isEmpty else { throw MolecularError.invalidStructure("No MOL2 atom section was found.") }
        if bonds.isEmpty { bonds = BondInference.infer(atoms: atoms) }
        return MolecularStructure(name: moleculeName, atoms: atoms, bonds: bonds)
    }
}

public struct XYZParser: Sendable {
    public init() {}

    public func parseTrajectory(_ data: Data, name: String = "XYZ") throws -> MolecularTrajectory {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidStructure("The XYZ file is not readable text.")
        }
        return try parseTrajectory(text, name: name)
    }

    public func parseTrajectory(_ text: String, name: String = "XYZ") throws -> MolecularTrajectory {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let sharedID = UUID()
        var index = 0
        var frames: [MolecularStructure] = []
        while index < lines.count {
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
            guard index < lines.count, let count = Int(lines[index].trimmingCharacters(in: .whitespaces)), count > 0 else { break }
            index += 1
            let comment = index < lines.count ? lines[index].trimmingCharacters(in: .whitespaces) : ""
            index += 1
            guard index + count <= lines.count else { throw MolecularError.invalidStructure("The XYZ frame is incomplete.") }
            var atoms: [Atom] = []
            for atomIndex in 0..<count {
                let values = lines[index + atomIndex].split(whereSeparator: \.isWhitespace).map(String.init)
                guard values.count >= 4, let x = Float(values[1]), let y = Float(values[2]), let z = Float(values[3]) else {
                    throw MolecularError.invalidStructure("An XYZ coordinate row is invalid.")
                }
                atoms.append(Atom(
                    id: atomIndex,
                    serial: atomIndex + 1,
                    name: "\(values[0])\(atomIndex + 1)",
                    element: values[0],
                    residueName: "MOL",
                    residueNumber: 1,
                    chainID: "X",
                    position: Vector3(x: x, y: y, z: z),
                    isHetero: true
                ))
            }
            index += count
            frames.append(MolecularStructure(
                id: sharedID,
                name: comment.nilIfEmpty ?? "\(name) · Frame \(frames.count + 1)",
                atoms: atoms,
                bonds: BondInference.infer(atoms: atoms)
            ))
        }
        guard let atomCount = frames.first?.atoms.count, !frames.isEmpty,
              frames.allSatisfy({ $0.atoms.count == atomCount }) else {
            throw MolecularError.invalidStructure("No consistent XYZ frames were found.")
        }
        return MolecularTrajectory(name: name, frames: frames)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
