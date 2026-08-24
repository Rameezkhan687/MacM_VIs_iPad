import Testing
@testable import MoleculePadCore

struct SelectionAndMeasurementsTests {
    @Test func selectsStructureParts() {
        let structure = SampleData.miniProtein
        let engine = MolecularSelectionEngine()

        #expect(engine.atomIDs(in: structure, matching: .chain("a")).count == 20)
        #expect(engine.atomIDs(in: structure, matching: .residueNumber(2)).count == 4)
        #expect(engine.atomIDs(in: structure, matching: .element("O")).count == 5)
        #expect(engine.atomIDs(in: structure, matching: .atomName("CA")).count == 4)
        #expect(engine.atomIDs(in: structure, matching: .ligand).isEmpty)
    }

    @Test func calculatesDistanceAngleAndTorsion() {
        let p0 = Vector3(x: 1, y: 0, z: 0)
        let p1 = Vector3(x: 0, y: 0, z: 0)
        let p2 = Vector3(x: 0, y: 1, z: 0)
        let p3 = Vector3(x: 0, y: 1, z: 1)

        #expect(MolecularMeasurements.distance(p0, p1) == 1)
        #expect(abs((MolecularMeasurements.angle(p0, p1, p2) ?? 0) - 90) < 0.001)
        #expect(abs(abs(MolecularMeasurements.torsion(p0, p1, p2, p3) ?? 0) - 90) < 0.001)
    }
}
