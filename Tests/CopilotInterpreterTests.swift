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

    @Test func plansMolecularSurfaceRequest() {
        let plan = copilot.plan("Show a molecular surface as a mesh with surface opacity 0.6 and probe radius 1.2")

        #expect(plan.commands == ["surface show", "surface style mesh", "surface opacity 0.6", "surface probe 1.2"])
    }

    @Test func plansTrajectoryControl() {
        #expect(copilot.plan("Play the trajectory").commands == ["trajectory play"])
        #expect(copilot.plan("Jump to trajectory frame 14").commands == ["trajectory frame 14"])
    }

    @Test func plansBiologicalAssembly() {
        #expect(copilot.plan("Show biological assembly 2").commands == ["assembly 2"])
        #expect(copilot.plan("Return to the asymmetric unit").commands == ["assembly asymmetric"])
    }

    @Test func plansAlternateLocation() {
        #expect(copilot.plan("Show alternate location B").commands == ["altloc b"])
        #expect(copilot.plan("Use primary coordinates").commands == ["altloc primary"])
    }

    @Test func plansPresentationControls() {
        let plan = copilot.plan("Use soft lighting, label residues, show axes and the scale bar, then use the top view")
        #expect(plan.commands == ["label residues", "lighting soft", "view top", "axes show", "scalebar show"])
        #expect(copilot.plan("Start presentation mode").commands == ["presentation start"])
        #expect(copilot.plan("Exit presentation mode").commands == ["presentation stop"])
    }

    @Test func plansSpecializedRepresentations() {
        #expect(copilot.plan("Show nucleotides").commands == ["style nucleotides"])
        #expect(copilot.plan("Use thermal ellipsoids").commands == ["style thermal"])
        #expect(copilot.plan("Draw an arrow between selected atoms").commands == ["arrow show"])
    }

    @Test func plansAnalysisAndComparison() {
        let analysis = copilot.plan("Find hydrogen bonds and steric clashes, then measure volume")
        #expect(analysis.commands == ["hbonds", "clashes", "measure volume"])
        #expect(copilot.plan("Align chains A and B").commands == ["align chains a b"])
        #expect(copilot.plan("Use this as reference").commands == ["reference set"])
        #expect(copilot.plan("Calculate RMSD to reference").commands == ["rmsd reference"])
        #expect(copilot.plan("Find cavities and chain interfaces").commands == ["cavities", "interfaces"])
        #expect(copilot.plan("Calculate sequence conservation").commands == ["conservation"])
        #expect(copilot.plan("Download AlphaFold model P07550").commands == ["alphafold p07550"])
        #expect(copilot.plan("Run protein BLAST").commands == ["blast protein"])
    }

    @Test func plansMapProcessingAndFitting() {
        let plan = copilot.plan("Show orthogonal slices, smooth the map, segment the map, and fit the structure to the map")
        #expect(plan.commands == ["map style slices", "map smooth 1", "map segment", "fit map"])
        #expect(copilot.plan("Create a difference map").commands == ["map difference"])
        #expect(copilot.plan("Zone the map within 4 angstroms").commands == ["map zone 4"])
    }

    @Test func plansMolecularEditing() {
        let plan = copilot.plan("Delete selected atoms, add hydrogens, assign charges, and minimize the structure")
        #expect(plan.commands == ["delete selected", "addh", "charges", "minimize"])
        #expect(copilot.plan("Mutate the selected residue to alanine").commands == ["mutate ala"])
        #expect(copilot.plan("Analyze docking pose").commands == ["dock analyze"])
        #expect(copilot.plan("Undo that").commands == ["undo"])
    }
}
