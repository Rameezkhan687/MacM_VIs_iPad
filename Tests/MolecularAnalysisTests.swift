import Testing
@testable import MoleculePadCore

struct MolecularAnalysisTests {
    private let engine = MolecularAnalysisEngine()

    @Test func detectsInteractionsAndMetrics() {
        let atoms = [
            Atom(id: 0, serial: 1, name: "N", element: "N", residueName: "ALA", residueNumber: 1, chainID: "A", position: .zero),
            Atom(id: 1, serial: 2, name: "O", element: "O", residueName: "GLY", residueNumber: 2, chainID: "A", position: Vector3(x: 0, y: 0, z: 3)),
            Atom(id: 2, serial: 3, name: "C", element: "C", residueName: "GLY", residueNumber: 2, chainID: "A", position: Vector3(x: 0, y: 0, z: 1))
        ]
        let structure = MolecularStructure(name: "Test", atoms: atoms, bonds: [Bond(atom1: 1, atom2: 2)])

        #expect(engine.hydrogenBonds(in: structure).count == 1)
        #expect(engine.contacts(in: structure).count >= 1)
        #expect(engine.estimatedSurfaceArea(of: atoms) > 0)
        #expect(engine.estimatedVolume(of: atoms) > 0)
        #expect(engine.principalAxis(of: atoms).length > 0.99)
    }

    @Test func extractsAndAlignsSequences() {
        let structure = SampleData.miniProtein
        let sequences = engine.sequences(in: structure)
        let alignment = engine.align("ACDE", "ACE")

        #expect(sequences.count == 1)
        #expect(!sequences[0].codes.isEmpty)
        #expect(alignment.first.count == alignment.second.count)
        #expect(alignment.identity > 0.7)
    }

    @Test func superposesTranslatedStructures() {
        let reference = SampleData.miniProtein
        var moving = reference
        moving.name = "Moved"
        for index in moving.atoms.indices {
            moving.atoms[index].position = moving.atoms[index].position + Vector3(x: 4, y: -2, z: 7)
        }
        let comparison = engine.superpose(moving, onto: reference)

        #expect(comparison?.matchedAtomCount == reference.atoms.count)
        #expect((comparison?.rmsd ?? 1) < 0.001)
    }

    @Test func fitsPlaneFindsInterfacesAndConservation() {
        let planar = [
            Atom(id: 0, serial: 1, name: "A", element: "C", residueName: "GLY", residueNumber: 1, chainID: "A", position: Vector3(x: 0, y: 0, z: 2)),
            Atom(id: 1, serial: 2, name: "B", element: "C", residueName: "GLY", residueNumber: 1, chainID: "A", position: Vector3(x: 1, y: 0, z: 2)),
            Atom(id: 2, serial: 3, name: "C", element: "C", residueName: "GLY", residueNumber: 1, chainID: "A", position: Vector3(x: 0, y: 1, z: 2)),
            Atom(id: 3, serial: 4, name: "D", element: "C", residueName: "GLY", residueNumber: 1, chainID: "B", position: Vector3(x: 0, y: 0, z: 5))
        ]
        let structure = MolecularStructure(name: "Interface", atoms: planar, bonds: [])
        let plane = engine.bestFitPlane(of: Array(planar.prefix(3)))
        let conservation = engine.conservation(of: ["ACDE", "ACDF", "ACDG"])

        #expect((plane?.rmsd ?? 1) < 0.001)
        #expect(engine.interfaces(in: structure).count == 1)
        #expect(conservation?.consensus.hasPrefix("ACD") == true)
        #expect(conservation?.scores[0] == 1)
    }
}
