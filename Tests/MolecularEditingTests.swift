import Testing
@testable import MoleculePadCore

struct MolecularEditingTests {
    private let editor = MolecularEditor()

    @Test func addsDeletesMutatesAndBonds() {
        let original = SampleData.miniProtein
        let added = editor.addingAtom(to: original, element: "ZN", position: .zero)
        let bonded = editor.addingBond(0, added.atoms.last!.id, to: added)
        let mutated = editor.mutatingResidue(chainID: "A", residueNumber: original.atoms[0].residueNumber, to: "VAL", in: bonded)
        let deleted = editor.deletingAtoms([added.atoms.last!.id], from: mutated)

        #expect(added.atoms.count == original.atoms.count + 1)
        #expect(bonded.bonds.count == added.bonds.count + 1)
        #expect(mutated.atoms[0].residueName == "VAL")
        #expect(deleted.atoms.count == original.atoms.count)
    }

    @Test func preparesAndMinimizes() {
        let original = SampleData.miniProtein
        let prepared = editor.dockPrepared(original)
        let minimized = editor.minimized(prepared, iterations: 3)

        #expect(prepared.atoms.count >= original.atoms.count)
        #expect(prepared.atoms.contains { $0.element == "H" })
        #expect(prepared.atoms.contains { $0.partialCharge != 0 })
        #expect(minimized.atoms.count == prepared.atoms.count)
    }

    @Test func rotatesBondAndTranslatesSelection() throws {
        let original = SampleData.miniProtein
        let bond = try #require(original.bonds.first)
        let rotated = editor.rotatedAroundBond(bond.atom1, bond.atom2, degrees: 30, in: original)
        let moved = editor.translated([0], by: Vector3(x: 1, y: 0, z: 0), in: original)

        #expect(rotated.atoms.count == original.atoms.count)
        #expect(moved.atoms[0].position.x == original.atoms[0].position.x + 1)
    }
}
