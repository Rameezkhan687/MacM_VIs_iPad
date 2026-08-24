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
}
