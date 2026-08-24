import Testing
@testable import MoleculePadCore

@Suite struct AnnotationsTests {
    @Test func clampsNormalizedCanvasCoordinates() {
        let point = CanvasPoint(x: -2, y: 4)
        #expect(point.x == 0)
        #expect(point.y == 1)
    }

    @Test func retainsPseudobondGroupAndColor() {
        let bond = CustomPseudobond(atom1: 2, atom2: 7, group: "Restraints", color: [1, 0, 0, 1])
        #expect(bond.group == "Restraints")
        #expect(bond.atom1 == 2 && bond.atom2 == 7)
    }
}
