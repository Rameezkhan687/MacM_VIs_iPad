import Testing
@testable import MoleculePadCore

struct CopilotInterpreterTests {
    private let copilot = CopilotInterpreter()

    @Test func plansCompoundProteinRequest() {
        let plan = copilot.plan("Download protein 1CRN, show it as a cartoon, and give each chain a different color")

        #expect(plan.commands == ["open 1crn", "style cartoon", "color chain"])
        #expect(plan.isActionable)
    }

    @Test func plansEMDBContourRequest() {
        let plan = copilot.plan("Load EMDB 1001 and set the contour level to 0.8")

        #expect(plan.commands == ["open emd-1001", "surface level 0.8"])
    }

    @Test func handlesVisibilityAndSelection() {
        let plan = copilot.plan("Please hide the density map and clear my selection")

        #expect(plan.commands == ["hide map", "select clear"])
    }

    @Test func acceptsDirectTerminalCommand() {
        let plan = copilot.plan("style sticks")

        #expect(plan.commands == ["style sticks"])
    }

    @Test func explainsCurrentLimits() {
        let plan = copilot.plan("Calculate the electrostatic potential")

        #expect(!plan.isActionable)
        #expect(plan.commands.isEmpty)
        #expect(plan.summary.contains("currently"))
    }

    @Test func plansPlainLanguageSelections() {
        #expect(copilot.plan("Select chain A").commands == ["select chain a"])
        #expect(copilot.plan("Highlight residue 42").commands == ["select residue 42"])
        #expect(copilot.plan("Select all oxygen atoms").commands == ["select element O"])
        #expect(copilot.plan("Choose the ligand").commands == ["select ligand"])
    }
}
