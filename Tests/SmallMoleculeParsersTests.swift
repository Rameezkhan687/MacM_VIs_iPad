import Foundation
import Testing
@testable import MoleculePadCore

struct SmallMoleculeParsersTests {
    @Test func parsesSDF() throws {
        let sdf = """
        Ethane
          MoleculePad

          2  1  0  0  0  0            999 V2000
            0.0000    0.0000    0.0000 C   0  0  0  0  0  0
            1.5400    0.0000    0.0000 C   0  0  0  0  0  0
          1  2  1  0  0  0  0
        M  END
        $$$$
        """
        let structure = try SDFParser().parse(sdf)
        #expect(structure.name == "Ethane")
        #expect(structure.atoms.count == 2)
        #expect(structure.bonds == [Bond(atom1: 0, atom2: 1)])
    }

    @Test func parsesMOL2() throws {
        let mol2 = """
        @<TRIPOS>MOLECULE
        Water
        3 2
        SMALL
        @<TRIPOS>ATOM
        1 O1 0 0 0 O.3 1 HOH
        2 H1 0.95 0 0 H 1 HOH
        3 H2 -0.24 0.92 0 H 1 HOH
        @<TRIPOS>BOND
        1 1 2 1
        2 1 3 1
        """
        let structure = try MOL2Parser().parse(mol2)
        #expect(structure.name == "Water")
        #expect(structure.atoms.count == 3)
        #expect(structure.bonds.count == 2)
    }

    @Test func parsesXYZTrajectory() throws {
        let xyz = """
        2
        frame one
        H 0 0 0
        H 0 0 0.74
        2
        frame two
        H 0 0 0
        H 0 0 0.80
        """
        let trajectory = try XYZParser().parseTrajectory(xyz)
        #expect(trajectory.frameCount == 2)
        #expect(trajectory.frames[1].atoms[1].position.z == 0.8)
    }
}
