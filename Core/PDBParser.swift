import Foundation

public struct PDBParser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "Structure") throws -> MolecularStructure {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidPDB("The file is not readable text.")
        }
        return try parse(text, name: name)
    }

    public func parse(_ text: String, name: String = "Structure") throws -> MolecularStructure {
        guard let first = try parseTrajectory(text, name: name).frames.first else {
            throw MolecularError.invalidPDB("No coordinate models were found.")
        }
        return first
    }

    public func parseTrajectory(_ data: Data, name: String = "Trajectory") throws -> MolecularTrajectory {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidPDB("The file is not readable text.")
        }
        return try parseTrajectory(text, name: name)
    }

    public func parseTrajectory(_ text: String, name: String = "Trajectory") throws -> MolecularTrajectory {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let containsModels = lines.contains { field($0, 0, 6).trimmingCharacters(in: .whitespaces) == "MODEL" }
        let sharedID = UUID()
        guard containsModels else {
            return MolecularTrajectory(name: name, frames: [try parseModel(text, name: name, id: sharedID)])
        }

        let annotationRecords = lines.filter {
            let record = field($0, 0, 6).trimmingCharacters(in: .whitespaces)
            return record == "HELIX" || record == "SHEET"
        }
        let connectionRecords = lines.filter {
            field($0, 0, 6).trimmingCharacters(in: .whitespaces) == "CONECT"
        }
        var blocks: [[String]] = []
        var current: [String] = []
        var insideModel = false
        for line in lines {
            let record = field(line, 0, 6).trimmingCharacters(in: .whitespaces)
            if record == "MODEL" {
                if insideModel, !current.isEmpty { blocks.append(current) }
                current = []
                insideModel = true
            } else if record == "ENDMDL" {
                if insideModel, !current.isEmpty { blocks.append(current) }
                current = []
                insideModel = false
            } else if insideModel && (record == "ATOM" || record == "HETATM") {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        let frames = try blocks.enumerated().map { index, block in
            try parseModel(
                (annotationRecords + block + connectionRecords).joined(separator: "\n"),
                name: "\(name) · Frame \(index + 1)",
                id: sharedID
            )
        }
        guard let expected = frames.first?.atoms.count,
              expected > 0,
              frames.allSatisfy({ $0.atoms.count == expected }) else {
            throw MolecularError.invalidPDB("Coordinate models contain different atom counts.")
        }
        return MolecularTrajectory(name: name, frames: frames)
    }

    private func parseModel(_ text: String, name: String, id: UUID) throws -> MolecularStructure {
        var atoms: [Atom] = []
        var serialToID: [Int: Int] = [:]
        var explicitBonds = Set<Bond>()
        var secondaryStructure: [SecondaryStructureSegment] = []
        var atomIndexByIdentity: [String: Int] = [:]
        var alternatePositions: [String: [Int: Vector3]] = [:]

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let record = field(line, 0, 6).trimmingCharacters(in: .whitespaces)
            if record == "ATOM" || record == "HETATM" {
                let alternateLocation = field(line, 16, 17).trimmingCharacters(in: .whitespaces)
                guard
                    let serial = Int(field(line, 6, 11).trimmingCharacters(in: .whitespaces)),
                    let x = Float(field(line, 30, 38).trimmingCharacters(in: .whitespaces)),
                    let y = Float(field(line, 38, 46).trimmingCharacters(in: .whitespaces)),
                    let z = Float(field(line, 46, 54).trimmingCharacters(in: .whitespaces))
                else { continue }

                let atomName = field(line, 12, 16).trimmingCharacters(in: .whitespaces)
                let rawElement = field(line, 76, 78).trimmingCharacters(in: .whitespaces)
                let chainID = field(line, 21, 22).trimmingCharacters(in: .whitespaces)
                let residueNumber = Int(field(line, 22, 26).trimmingCharacters(in: .whitespaces)) ?? 0
                let identity = "\(chainID)|\(residueNumber)|\(atomName)"
                let position = Vector3(x: x, y: y, z: z)
                if let atomID = atomIndexByIdentity[identity] {
                    serialToID[serial] = atomID
                    if !alternateLocation.isEmpty {
                        alternatePositions[alternateLocation, default: [:]][atomID] = position
                        if alternateLocation == "A" { atoms[atomID].position = position }
                    }
                    continue
                }
                let id = atoms.count
                atoms.append(Atom(
                    id: id,
                    serial: serial,
                    name: atomName,
                    element: rawElement.isEmpty ? ElementTable.inferredElement(atomName: atomName) : rawElement,
                    residueName: field(line, 17, 20).trimmingCharacters(in: .whitespaces),
                    residueNumber: residueNumber,
                    chainID: chainID,
                    position: position,
                    occupancy: Float(field(line, 54, 60).trimmingCharacters(in: .whitespaces)) ?? 1,
                    bFactor: Float(field(line, 60, 66).trimmingCharacters(in: .whitespaces)) ?? 0,
                    isHetero: record == "HETATM"
                ))
                serialToID[serial] = id
                atomIndexByIdentity[identity] = id
                if !alternateLocation.isEmpty {
                    alternatePositions[alternateLocation, default: [:]][id] = position
                }
            } else if record == "CONECT" {
                let values = stride(from: 6, to: line.count, by: 5).compactMap {
                    Int(field(line, $0, min($0 + 5, line.count)).trimmingCharacters(in: .whitespaces))
                }
                guard let sourceSerial = values.first, let sourceID = serialToID[sourceSerial] else { continue }
                for targetSerial in values.dropFirst() {
                    if let targetID = serialToID[targetSerial], targetID != sourceID {
                        explicitBonds.insert(Bond(atom1: sourceID, atom2: targetID))
                    }
                }
            } else if record == "HELIX" {
                appendSecondaryStructure(
                    kind: .helix,
                    startChain: field(line, 19, 20),
                    startResidue: field(line, 21, 25),
                    endChain: field(line, 31, 32),
                    endResidue: field(line, 33, 37),
                    to: &secondaryStructure
                )
            } else if record == "SHEET" {
                appendSecondaryStructure(
                    kind: .sheet,
                    startChain: field(line, 21, 22),
                    startResidue: field(line, 22, 26),
                    endChain: field(line, 32, 33),
                    endResidue: field(line, 33, 37),
                    to: &secondaryStructure
                )
            }
        }

        guard !atoms.isEmpty else {
            throw MolecularError.invalidPDB("No ATOM or HETATM records were found.")
        }

        let bonds = explicitBonds.isEmpty ? BondInference.infer(atoms: atoms) : Array(explicitBonds)
        return MolecularStructure(
            id: id,
            name: name,
            atoms: atoms,
            bonds: bonds.sorted {
                $0.atom1 == $1.atom1 ? $0.atom2 < $1.atom2 : $0.atom1 < $1.atom1
            },
            secondaryStructure: secondaryStructure,
            alternateConformations: alternatePositions.keys.sorted().map {
                AlternateConformation(id: $0, positions: alternatePositions[$0] ?? [:])
            }
        )
    }

    private func appendSecondaryStructure(
        kind: SecondaryStructureKind,
        startChain: String,
        startResidue: String,
        endChain: String,
        endResidue: String,
        to segments: inout [SecondaryStructureSegment]
    ) {
        let chainID = startChain.trimmingCharacters(in: .whitespaces)
        let endingChainID = endChain.trimmingCharacters(in: .whitespaces)
        guard endingChainID.isEmpty || chainID == endingChainID,
              let start = Int(startResidue.trimmingCharacters(in: .whitespaces)),
              let end = Int(endResidue.trimmingCharacters(in: .whitespaces)) else { return }
        segments.append(SecondaryStructureSegment(
            kind: kind,
            chainID: chainID,
            startResidue: start,
            endResidue: end
        ))
    }

    private func field(_ line: String, _ start: Int, _ end: Int) -> String {
        guard start < line.count, start < end else { return "" }
        let lower = line.index(line.startIndex, offsetBy: start)
        let upper = line.index(line.startIndex, offsetBy: min(end, line.count))
        return String(line[lower..<upper])
    }
}
