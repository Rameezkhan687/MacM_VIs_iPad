import Testing
@testable import MoleculePadCore

struct PDBParserTests {
    @Test func parsesBundledStructure() throws {
        let structure = try PDBParser().parse(SampleData.miniProteinPDB, name: "Test")
        #expect(structure.atoms.count == 20)
        #expect(structure.bonds.count > 15)
        #expect(structure.atoms.first?.element == "N")
        #expect(structure.chainIDs == ["A"])
    }

    @Test func rejectsEmptyPDB() {
        #expect(throws: MolecularError.self) {
            try PDBParser().parse("HEADER empty")
        }
    }

    @Test func centerAndRadius() {
        let structure = SampleData.miniProtein
        #expect(structure.radius > 5)
        #expect(abs(structure.center.y) < 2)
    }

    @Test func parsesHelixAndSheetAnnotations() throws {
        let annotatedPDB = """
        HELIX    1  HA GLY A   86  GLY A   94  1                                   9
        SHEET    1   A 5 THR A 107  ARG A 110  0
        \(SampleData.miniProteinPDB)
        """
        let structure = try PDBParser().parse(annotatedPDB)

        #expect(structure.secondaryStructure.count == 2)
        #expect(structure.secondaryStructure[0] == SecondaryStructureSegment(
            kind: .helix,
            chainID: "A",
            startResidue: 86,
            endResidue: 94
        ))
        #expect(structure.secondaryStructure[1].kind == .sheet)
        #expect(structure.secondaryStructure[1].startResidue == 107)
        #expect(structure.secondaryStructure[1].endResidue == 110)
        #expect(structure.secondaryStructureKind(chainID: "A", residueNumber: 90) == .helix)
        #expect(structure.secondaryStructureKind(chainID: "A", residueNumber: 105) == .coil)
    }

    @Test func parsesMultiModelTrajectory() throws {
        let trajectoryPDB = """
        MODEL        1
        \(SampleData.miniProteinPDB)
        ENDMDL
        MODEL        2
        \(SampleData.miniProteinPDB)
        ENDMDL
        """
        let trajectory = try PDBParser().parseTrajectory(trajectoryPDB, name: "Motion")

        #expect(trajectory.frameCount == 2)
        #expect(trajectory.frames[0].atoms.count == 20)
        #expect(trajectory.frames[0].id == trajectory.frames[1].id)
        #expect(trajectory.frames[1].name.contains("Frame 2"))
    }
}
