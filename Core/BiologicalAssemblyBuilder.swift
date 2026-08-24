import Foundation

public struct BiologicalAssemblyBuilder: Sendable {
    public init() {}

    public func expandedStructure(
        from structure: MolecularStructure,
        assemblyID: String,
        maximumAtoms: Int = 200_000
    ) -> MolecularStructure? {
        guard let assembly = structure.biologicalAssemblies.first(where: { $0.id == assemblyID }) else { return nil }
        let sourceByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
        var atoms: [Atom] = []
        var bonds: [Bond] = []
        var secondary: [SecondaryStructureSegment] = []

        for (instanceIndex, instance) in assembly.instances.enumerated() {
            let included = structure.atoms.filter { instance.chainIDs.isEmpty || instance.chainIDs.contains($0.chainID) }
            guard atoms.count + included.count <= maximumAtoms else { break }
            var idMap: [Int: Int] = [:]
            let suffix = assembly.instances.count > 1 ? "·\(instanceIndex + 1)" : ""
            for source in included {
                let id = atoms.count
                idMap[source.id] = id
                atoms.append(Atom(
                    id: id,
                    serial: id + 1,
                    name: source.name,
                    element: source.element,
                    residueName: source.residueName,
                    residueNumber: source.residueNumber,
                    chainID: source.chainID + suffix,
                    position: instance.transform.applying(to: source.position),
                    occupancy: source.occupancy,
                    bFactor: source.bFactor,
                    isHetero: source.isHetero
                ))
            }
            for bond in structure.bonds {
                guard sourceByID[bond.atom1] != nil,
                      let first = idMap[bond.atom1], let second = idMap[bond.atom2] else { continue }
                bonds.append(Bond(atom1: first, atom2: second, order: bond.order))
            }
            for segment in structure.secondaryStructure where instance.chainIDs.isEmpty || instance.chainIDs.contains(segment.chainID) {
                secondary.append(SecondaryStructureSegment(
                    kind: segment.kind,
                    chainID: segment.chainID + suffix,
                    startResidue: segment.startResidue,
                    endResidue: segment.endResidue
                ))
            }
        }
        guard !atoms.isEmpty else { return nil }
        return MolecularStructure(
            name: "\(structure.name) · Assembly \(assembly.id)",
            atoms: atoms,
            bonds: bonds,
            secondaryStructure: secondary
        )
    }
}
