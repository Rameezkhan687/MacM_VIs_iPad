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
        var atoms: [Atom] = []
        var serialToID: [Int: Int] = [:]
        var explicitBonds = Set<Bond>()

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let record = field(line, 0, 6).trimmingCharacters(in: .whitespaces)
            if record == "ATOM" || record == "HETATM" {
                let alternateLocation = field(line, 16, 17).trimmingCharacters(in: .whitespaces)
                guard alternateLocation.isEmpty || alternateLocation == "A" else { continue }
                guard
                    let serial = Int(field(line, 6, 11).trimmingCharacters(in: .whitespaces)),
                    let x = Float(field(line, 30, 38).trimmingCharacters(in: .whitespaces)),
                    let y = Float(field(line, 38, 46).trimmingCharacters(in: .whitespaces)),
                    let z = Float(field(line, 46, 54).trimmingCharacters(in: .whitespaces))
                else { continue }

                let atomName = field(line, 12, 16).trimmingCharacters(in: .whitespaces)
                let rawElement = field(line, 76, 78).trimmingCharacters(in: .whitespaces)
                let id = atoms.count
                atoms.append(Atom(
                    id: id,
                    serial: serial,
                    name: atomName,
                    element: rawElement.isEmpty ? ElementTable.inferredElement(atomName: atomName) : rawElement,
                    residueName: field(line, 17, 20).trimmingCharacters(in: .whitespaces),
                    residueNumber: Int(field(line, 22, 26).trimmingCharacters(in: .whitespaces)) ?? 0,
                    chainID: field(line, 21, 22).trimmingCharacters(in: .whitespaces),
                    position: Vector3(x: x, y: y, z: z),
                    occupancy: Float(field(line, 54, 60).trimmingCharacters(in: .whitespaces)) ?? 1,
                    bFactor: Float(field(line, 60, 66).trimmingCharacters(in: .whitespaces)) ?? 0,
                    isHetero: record == "HETATM"
                ))
                serialToID[serial] = id
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
            }
        }

        guard !atoms.isEmpty else {
            throw MolecularError.invalidPDB("No ATOM or HETATM records were found.")
        }

        let bonds = explicitBonds.isEmpty ? BondInference.infer(atoms: atoms) : Array(explicitBonds)
        return MolecularStructure(name: name, atoms: atoms, bonds: bonds.sorted {
            $0.atom1 == $1.atom1 ? $0.atom2 < $1.atom2 : $0.atom1 < $1.atom1
        })
    }

    private func field(_ line: String, _ start: Int, _ end: Int) -> String {
        guard start < line.count, start < end else { return "" }
        let lower = line.index(line.startIndex, offsetBy: start)
        let upper = line.index(line.startIndex, offsetBy: min(end, line.count))
        return String(line[lower..<upper])
    }
}
