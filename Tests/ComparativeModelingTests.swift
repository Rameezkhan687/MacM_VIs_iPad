import Testing
@testable import MoleculePadCore

@Suite struct ComparativeModelingTests {
    @Test func fillsBackboneAcrossResidueGap() {
        let atoms = [
            Atom(id: 0, serial: 1, name: "CA", element: "C", residueName: "ALA", residueNumber: 1, chainID: "A", position: .zero),
            Atom(id: 1, serial: 2, name: "CA", element: "C", residueName: "GLY", residueNumber: 3, chainID: "A", position: Vector3(x: 7.6, y: 0, z: 0))
        ]
        let result = ComparativeModeler().fillingBackboneLoops(in: MolecularStructure(name: "Gap", atoms: atoms, bonds: []))
        #expect(result.atoms.filter { $0.residueNumber == 2 }.count == 4)
        #expect(result.atoms.contains { $0.residueNumber == 2 && $0.name == "CA" })
    }

    @Test func completesMissingTemplateAtomsWithoutReplacingExistingOnes() {
        let target = MolecularStructure(name: "Target", atoms: [
            Atom(id: 0, serial: 1, name: "CA", element: "C", residueName: "ALA", residueNumber: 1, chainID: "A", position: .zero)
        ], bonds: [])
        let template = MolecularStructure(name: "Template", atoms: [
            Atom(id: 0, serial: 1, name: "CA", element: "C", residueName: "ALA", residueNumber: 1, chainID: "A", position: Vector3(x: 9, y: 9, z: 9)),
            Atom(id: 1, serial: 2, name: "CB", element: "C", residueName: "ALA", residueNumber: 1, chainID: "A", position: Vector3(x: 1.5, y: 0, z: 0))
        ], bonds: [])
        let result = ComparativeModeler().completing(target, fromAlignedTemplate: template)
        #expect(result.atoms.count == 2)
        #expect(result.atoms.first?.position == .zero)
    }
}
