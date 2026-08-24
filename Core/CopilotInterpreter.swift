import Foundation

public struct CopilotPlan: Equatable, Sendable {
    public let commands: [String]
    public let summary: String

    public init(commands: [String], summary: String) {
        self.commands = commands
        self.summary = summary
    }

    public var isActionable: Bool { !commands.isEmpty }
}

public struct CopilotInterpreter: Sendable {
    public init() {}

    /// Validates one exact terminal command without executing it. Used to keep
    /// server-generated Copilot plans and declarative plug-ins inside the same
    /// audited command boundary as the on-device interpreter.
    public func isAllowedCommand(_ command: String) -> Bool {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\n"), !value.contains(";") else { return false }
        return directCommand(from: normalized(value)) != nil
    }

    public func plan(_ request: String) -> CopilotPlan {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CopilotPlan(commands: [], summary: "Tell me what you would like to see or change.")
        }

        let text = normalized(trimmed)
        var commands: [String] = []
        var actions: [String] = []

        if let emdbID = emdbIdentifier(in: text), containsAny(text, ["open", "load", "fetch", "download", "get", "emdb", "density map"]) {
            append("open emd-\(emdbID)", action: "download EMDB map EMD-\(emdbID)", to: &commands, actions: &actions)
        } else if let pdbID = pdbIdentifier(in: text), containsAny(text, ["open", "load", "fetch", "download", "get", "pdb", "protein", "structure", "molecule"]) {
            append("open \(pdbID)", action: "download PDB structure \(pdbID.uppercased())", to: &commands, actions: &actions)
        }
        if let accession = firstCapture(
            pattern: #"(?:alphafold|uniprot)(?:\s+(?:model|prediction|entry))?(?:\s+(?:for|of))?\s+([a-z0-9]{6,12}(?:-\d+)?)"#,
            in: text
        ) {
            append("alphafold \(accession)", action: "download AlphaFold prediction \(accession.uppercased())", to: &commands, actions: &actions)
        }

        if containsAny(text, ["cartoon", "ribbon"]) {
            append("style cartoon", action: "show the structure as a cartoon", to: &commands, actions: &actions)
        } else if containsAny(text, ["ball and stick", "ball-and-stick", "balls and sticks"]) {
            append("style ball", action: "use ball-and-stick representation", to: &commands, actions: &actions)
        } else if containsAny(text, ["spacefill", "space fill", "space-filling", "space filling", "full spheres", "van der waals"]) {
            append("style spacefill", action: "use space-filling spheres", to: &commands, actions: &actions)
        } else if containsAny(text, ["backbone", "trace only"]) {
            append("style backbone", action: "show the backbone trace", to: &commands, actions: &actions)
        } else if containsAny(text, ["nucleotide representation", "show nucleotides", "nucleic acid style", "dna style", "rna style"]) {
            append("style nucleotides", action: "show the nucleotide chains", to: &commands, actions: &actions)
        } else if containsAny(text, ["glycan representation", "show glycans", "carbohydrate style", "sugar representation"]) {
            append("style glycans", action: "show the glycan residues", to: &commands, actions: &actions)
        } else if containsAny(text, ["thermal ellipsoid", "thermal ellipsoids", "b-factor ellipsoid", "temperature ellipsoid"]) {
            append("style thermal", action: "show B-factor-scaled ellipsoids", to: &commands, actions: &actions)
        } else if containsAny(text, ["sticks", "stick representation", "as stick"]) {
            append("style sticks", action: "use stick representation", to: &commands, actions: &actions)
        }

        if containsAny(text, ["color by chain", "colour by chain", "each chain", "different chain", "chain colors", "chain colours"]) {
            append("color chain", action: "color each chain differently", to: &commands, actions: &actions)
        } else if containsAny(text, ["color by residue", "colour by residue", "residue colors", "residue colours"]) {
            append("color residue", action: "color by residue type", to: &commands, actions: &actions)
        } else if containsAny(text, ["color by element", "colour by element", "element colors", "element colours", "cpk colors", "cpk colours"]) {
            append("color element", action: "color atoms by element", to: &commands, actions: &actions)
        } else if containsAny(text, ["one color", "one colour", "single color", "single colour", "monochrome", "mono color", "mono colour"]) {
            append("color mono", action: "use one color", to: &commands, actions: &actions)
        }

        if containsAny(text, ["hide labels", "remove labels", "turn labels off", "no labels"]) {
            append("label none", action: "hide molecular labels", to: &commands, actions: &actions)
        } else if containsAny(text, ["label selected", "label my selection", "show selection labels"]) {
            append("label selected", action: "label selected atoms", to: &commands, actions: &actions)
        } else if containsAny(text, ["label residues", "residue labels", "show residue names"]) {
            append("label residues", action: "label residues", to: &commands, actions: &actions)
        } else if containsAny(text, ["label chains", "chain labels"]) {
            append("label chains", action: "label chains", to: &commands, actions: &actions)
        } else if containsAny(text, ["label atoms", "atom labels"]) {
            append("label atoms", action: "label atoms", to: &commands, actions: &actions)
        }

        for preset in ["studio", "soft", "flat", "dramatic"] where text.contains("\(preset) lighting") || text.contains("lighting \(preset)") {
            append("lighting \(preset)", action: "use \(preset) lighting", to: &commands, actions: &actions)
            break
        }
        for direction in ["front", "back", "left", "right", "top", "bottom"]
        where text.contains("\(direction) view") || text.contains("view from the \(direction)") {
            append("view \(direction)", action: "use the \(direction) view", to: &commands, actions: &actions)
            break
        }
        if containsAny(text, ["show axes", "display axes", "turn axes on"]) {
            append("axes show", action: "show coordinate axes", to: &commands, actions: &actions)
        } else if containsAny(text, ["hide axes", "remove axes", "turn axes off"]) {
            append("axes hide", action: "hide coordinate axes", to: &commands, actions: &actions)
        }
        if text.contains("scale bar"), containsAny(text, ["show", "display", "turn on"]),
           !containsAny(text, ["hide", "remove", "turn off"]) {
            append("scalebar show", action: "show an ångström scale bar", to: &commands, actions: &actions)
        } else if containsAny(text, ["hide scale bar", "remove scale bar", "turn scale bar off"]) {
            append("scalebar hide", action: "hide the scale bar", to: &commands, actions: &actions)
        }
        if containsAny(text, ["show arrow", "draw an arrow", "arrow between selected", "selection arrow"]) {
            append("arrow show", action: "draw an arrow between the first two selected atoms", to: &commands, actions: &actions)
        } else if containsAny(text, ["hide arrow", "remove arrow"]) {
            append("arrow hide", action: "hide the selection arrow", to: &commands, actions: &actions)
        }
        if containsAny(text, ["stop presentation", "exit presentation", "leave presentation", "end presentation"]) {
            append("presentation stop", action: "leave presentation mode", to: &commands, actions: &actions)
        } else if containsAny(text, ["start presentation", "presentation mode", "present full screen", "show full screen"]) {
            append("presentation start", action: "enter presentation mode", to: &commands, actions: &actions)
        }

        if let level = contourLevel(in: text) {
            append("surface level \(level)", action: "set the map contour to \(level)", to: &commands, actions: &actions)
        }
        if containsAny(text, ["show volume", "solid volume", "volume rendering", "render volume"]) {
            append("map style volume", action: "show solid volume density", to: &commands, actions: &actions)
        } else if containsAny(text, ["show slices", "orthogonal slices", "map slices", "slice view"]) {
            append("map style slices", action: "show orthogonal map slices", to: &commands, actions: &actions)
        } else if containsAny(text, ["show isosurface", "map isosurface", "surface map style"]) {
            append("map style surface", action: "show the map as an isosurface", to: &commands, actions: &actions)
        }
        if let radius = firstCapture(pattern: #"(?:smooth|blur)(?:\s+the)?\s+map(?:\s+(?:by|radius))?\s*([0-9]+)?"#, in: text) {
            append("map smooth \(radius.isEmpty ? "1" : radius)", action: "smooth the map", to: &commands, actions: &actions)
        } else if containsAny(text, ["smooth map", "smooth the map", "blur map", "blur the map"]) {
            append("map smooth 1", action: "smooth the map", to: &commands, actions: &actions)
        }
        if containsAny(text, ["sharpen map", "sharpen the map"]) {
            append("map sharpen 1", action: "sharpen the map", to: &commands, actions: &actions)
        }
        if let radius = firstCapture(pattern: #"(?:zone|mask)(?:\s+the)?\s+map(?:\s+(?:within|to))?\s+([0-9]+(?:\.[0-9]+)?)"#, in: text) {
            append("map zone \(radius)", action: "zone the map within \(radius) Å of selected atoms", to: &commands, actions: &actions)
        }
        if containsAny(text, ["map statistics", "map stats", "density statistics"]) {
            append("map stats", action: "calculate map statistics", to: &commands, actions: &actions)
        }
        if containsAny(text, ["segment map", "segment the map", "find map regions", "density regions"]) {
            append("map segment", action: "segment connected density regions", to: &commands, actions: &actions)
        }
        if containsAny(text, ["save map reference", "set map reference"]) {
            append("map reference set", action: "save the current map as a reference", to: &commands, actions: &actions)
        }
        if containsAny(text, ["difference map", "subtract map", "map difference"]) {
            append("map difference", action: "create a difference map", to: &commands, actions: &actions)
        }
        if containsAny(text, ["fit structure to map", "fit the structure to the map", "fit atoms to map", "fit the atoms to the map", "fit into density", "dock into map"]) {
            let command = containsAny(text, ["rotate", "rotation", "rigid"]) ? "fit map rigid" : "fit map"
            append(command, action: "fit the atomic structure into the map", to: &commands, actions: &actions)
        } else if containsAny(text, ["fit map to map", "fit maps", "align maps", "register maps"]) {
            append("fit maps", action: "fit the map to the saved reference map", to: &commands, actions: &actions)
        }
        if containsAny(text, ["delete selected atoms", "remove selected atoms", "delete my selection"]) {
            append("delete selected", action: "delete the selected atoms", to: &commands, actions: &actions)
        }
        if containsAny(text, ["add a bond", "bond selected atoms", "connect selected atoms"]) {
            append("bond add", action: "add a bond between the selected atoms", to: &commands, actions: &actions)
        } else if containsAny(text, ["delete the bond", "remove selected bond", "break the bond"]) {
            append("bond delete", action: "delete the bond between selected atoms", to: &commands, actions: &actions)
        }
        if let residue = firstCapture(pattern: #"mutate(?:\s+the)?(?:\s+selected)?(?:\s+residue)?\s+(?:to\s+)?([a-z]{3})"#, in: text) {
            append("mutate \(residue)", action: "mutate the selected residue to \(residue.uppercased())", to: &commands, actions: &actions)
        }
        if containsAny(text, ["add hydrogens", "add hydrogen atoms", "protonate structure"]) {
            append("addh", action: "add hydrogens", to: &commands, actions: &actions)
        }
        if containsAny(text, ["assign charges", "calculate charges", "add partial charges"]) {
            append("charges", action: "assign simple partial charges", to: &commands, actions: &actions)
        }
        if containsAny(text, ["dock prep", "dockprep", "prepare for docking", "prepare structure for docking"]) {
            append("dockprep", action: "prepare the structure for docking", to: &commands, actions: &actions)
        }
        if containsAny(text, ["minimize structure", "minimize the structure", "minimize geometry", "minimize the geometry", "energy minimize", "relax structure"]) {
            append("minimize", action: "minimize the molecular geometry", to: &commands, actions: &actions)
        }
        if let degrees = firstCapture(pattern: #"(?:set|rotate|change)(?:\s+the)?\s+torsion(?:\s+(?:to|by))?\s+(-?[0-9]+(?:\.[0-9]+)?)"#, in: text) {
            append("torsion \(degrees)", action: "rotate the selected bond by \(degrees) degrees", to: &commands, actions: &actions)
        }
        if let degrees = firstCapture(pattern: #"(?:apply|set|rotate)?\s*rotamer(?:\s+(?:to|by))?\s+(-?[0-9]+(?:\.[0-9]+)?)"#, in: text) {
            append("rotamer \(degrees)", action: "apply a \(degrees)-degree side-chain rotamer", to: &commands, actions: &actions)
        }
        if containsAny(text, ["analyze docking pose", "analyze ligand pose", "docking analysis"]) {
            append("dock analyze", action: "analyze ligand contacts and clashes", to: &commands, actions: &actions)
        }
        if containsAny(text, ["model missing loops", "fill backbone gaps", "build missing loops"]) {
            append("model loops", action: "build backbone atoms across numbered residue gaps", to: &commands, actions: &actions)
        }
        if containsAny(text, ["complete from reference", "model from template", "add missing atoms from reference"]) {
            append("model reference", action: "complete the model from the aligned reference template", to: &commands, actions: &actions)
        }
        if text == "undo" || containsAny(text, ["undo that", "undo last edit"]) {
            append("undo", action: "undo the last edit", to: &commands, actions: &actions)
        } else if text == "redo" || containsAny(text, ["redo that", "redo edit"]) {
            append("redo", action: "redo the edit", to: &commands, actions: &actions)
        }

        if containsAny(text, ["hide molecular surface", "hide the molecular surface", "turn off molecular surface", "remove molecular surface"]) {
            append("surface hide", action: "hide the molecular surface", to: &commands, actions: &actions)
        } else if containsAny(text, ["molecular surface", "solvent surface", "accessible surface", "display surface", "show surface"]) {
            append("surface show", action: "build and show the molecular surface", to: &commands, actions: &actions)
        }
        if containsAny(text, ["surface mesh", "surface as a mesh", "mesh surface", "wire surface", "wireframe surface"]) {
            append("surface style mesh", action: "draw the molecular surface as a mesh", to: &commands, actions: &actions)
        } else if containsAny(text, ["surface dots", "dotted surface", "dot surface", "surface as dots"]) {
            append("surface style dots", action: "draw the molecular surface as dots", to: &commands, actions: &actions)
        } else if containsAny(text, ["solid surface", "surface solid", "filled surface"]) {
            append("surface style solid", action: "draw a solid molecular surface", to: &commands, actions: &actions)
        }
        if let opacity = molecularSurfaceOpacity(in: text) {
            append("surface opacity \(opacity)", action: "set the molecular-surface opacity to \(opacity)", to: &commands, actions: &actions)
        }
        if let probe = molecularSurfaceProbe(in: text) {
            append("surface probe \(probe)", action: "use a \(probe) Å surface probe", to: &commands, actions: &actions)
        }
        for property in ["element", "chain", "residue", "bfactor", "charge"]
        where text.contains("color surface by \(property)") || text.contains("surface color by \(property)") {
            append("surface color \(property)", action: "color the surface by \(property)", to: &commands, actions: &actions)
            break
        }

        if containsAny(text, ["hide the map", "hide map", "hide density", "hide the density", "turn off the map", "remove the map", "turn map off"]) {
            append("hide map", action: "hide the density map", to: &commands, actions: &actions)
        } else if containsAny(text, ["show the map", "show map", "show density", "turn on the map", "turn map on"]) {
            append("show map", action: "show the density map", to: &commands, actions: &actions)
        }

        if containsAny(text, ["hide atoms", "hide the atoms", "hide structure", "hide the structure", "hide protein", "turn atoms off"]) {
            append("hide atoms", action: "hide the atomic structure", to: &commands, actions: &actions)
        } else if containsAny(text, ["show atoms", "show the atoms", "show structure", "show the structure", "show protein", "turn atoms on"]) {
            append("show atoms", action: "show the atomic structure", to: &commands, actions: &actions)
        }

        if let selection = selectionCommand(in: text) {
            append(selection.command, action: selection.action, to: &commands, actions: &actions)
        }

        if containsAny(text, ["clear selection", "clear my selection", "clear the selection", "deselect", "select nothing", "remove selection"]) {
            append("select clear", action: "clear the selection", to: &commands, actions: &actions)
        }

        if containsAny(text, ["hydrogen bonds", "hydrogen bond", "h-bonds", "hbonds"]) {
            append("hbonds", action: "find hydrogen bonds", to: &commands, actions: &actions)
        }
        if containsAny(text, ["find contacts", "show contacts", "close contacts", "nonbonded contacts"]) {
            append("contacts", action: "find close contacts", to: &commands, actions: &actions)
        }
        if containsAny(text, ["find clashes", "show clashes", "steric clashes", "bad clashes"]) {
            append("clashes", action: "find steric clashes", to: &commands, actions: &actions)
        }
        if containsAny(text, ["find cavities", "show cavities", "detect cavities", "find pockets", "show pockets"]) {
            append("cavities", action: "detect enclosed molecular cavities", to: &commands, actions: &actions)
        }
        if containsAny(text, ["find interfaces", "show interfaces", "chain interfaces", "protein interfaces"]) {
            append("interfaces", action: "analyze chain interfaces", to: &commands, actions: &actions)
        }
        if containsAny(text, ["clear interactions", "remove pseudobonds", "hide interactions"]) {
            append("interactions clear", action: "clear interaction pseudobonds", to: &commands, actions: &actions)
        }
        if containsAny(text, ["add pseudobond", "create pseudobond", "connect selected with pseudobond"]) {
            append("pseudobond add custom", action: "add a custom pseudobond between the selected atoms", to: &commands, actions: &actions)
        }
        if containsAny(text, ["start drawing", "draw annotation", "annotate the view"]) {
            append("annotate start", action: "enable the 2D annotation canvas", to: &commands, actions: &actions)
        } else if containsAny(text, ["stop drawing", "finish annotation"]) {
            append("annotate stop", action: "stop drawing annotations", to: &commands, actions: &actions)
        } else if containsAny(text, ["clear annotations", "erase annotations"]) {
            append("annotate clear", action: "clear 2D annotations", to: &commands, actions: &actions)
        }
        for quantity in ["area", "volume", "centroid", "axis", "plane"]
        where text.contains("measure \(quantity)") || text.contains("calculate \(quantity)") || text.contains("report \(quantity)") {
            append("measure \(quantity)", action: "measure the \(quantity)", to: &commands, actions: &actions)
            break
        }
        if containsAny(text, ["show sequence", "extract sequence", "list sequences", "show the sequence"]) {
            append("sequence", action: "extract polymer sequences", to: &commands, actions: &actions)
        }
        if containsAny(text, ["sequence conservation", "show conservation", "calculate conservation", "conservation scores"]) {
            append("conservation", action: "calculate chain-sequence conservation", to: &commands, actions: &actions)
        }
        if containsAny(text, ["run blast", "protein blast", "blast the sequence", "search similar sequences"]) {
            append("blast protein", action: "submit the first protein chain to NCBI BLAST", to: &commands, actions: &actions)
        }
        if let pdbID = firstCapture(pattern: #"(?:find|search)(?:\s+for)?\s+(?:3d|structurally)?\s*similar(?:\s+to)?\s+([0-9][a-z0-9]{3})"#, in: text) {
            append("similar \(pdbID)", action: "search RCSB for 3D-similar structures", to: &commands, actions: &actions)
        } else if containsAny(text, ["find similar structures", "3d similarity search", "search structural neighbors"]) {
            append("similar current", action: "search RCSB for 3D-similar structures", to: &commands, actions: &actions)
        }
        if containsAny(text, ["run foldseek", "foldseek search", "search with foldseek"]) {
            append("foldseek", action: "run Foldseek on the configured compute provider", to: &commands, actions: &actions)
        }
        for provider in ["esmfold", "openfold", "boltz"]
        where text.contains("run \(provider)") || text.contains("predict with \(provider)") || text.contains("use \(provider)") {
            append("compute \(provider)", action: "run \(provider) on the configured compute provider", to: &commands, actions: &actions)
            break
        }
        if let chains = firstTwoCaptures(pattern: #"align\s+chains?\s+([a-z0-9]+)(?:\s+(?:and|to|with))?\s+([a-z0-9]+)"#, in: text) {
            append("align chains \(chains.0) \(chains.1)", action: "align chains \(chains.0.uppercased()) and \(chains.1.uppercased())", to: &commands, actions: &actions)
        }
        if containsAny(text, ["save reference", "set reference", "use as reference", "as reference", "remember this structure"]) {
            append("reference set", action: "save the current structure as the reference", to: &commands, actions: &actions)
        }
        if containsAny(text, ["match reference", "align to reference", "superpose on reference", "superimpose on reference"]) {
            append("match reference", action: "superpose the structure on the reference", to: &commands, actions: &actions)
        } else if containsAny(text, ["rmsd reference", "rmsd to reference", "compare to reference"]) {
            append("rmsd reference", action: "calculate fitted RMSD to the reference", to: &commands, actions: &actions)
        }

        if containsAny(text, ["play trajectory", "animate trajectory", "play the trajectory", "start trajectory", "animate the models"]) {
            append("trajectory play", action: "play the coordinate trajectory", to: &commands, actions: &actions)
        } else if containsAny(text, ["pause trajectory", "stop trajectory", "pause the trajectory", "stop the trajectory"]) {
            append("trajectory pause", action: "pause the coordinate trajectory", to: &commands, actions: &actions)
        } else if containsAny(text, ["next trajectory frame", "next frame"]) {
            append("trajectory next", action: "advance to the next coordinate frame", to: &commands, actions: &actions)
        } else if let frame = firstCapture(pattern: #"(?:trajectory\s+)?frame\s+([0-9]+)"#, in: text) {
            append("trajectory frame \(frame)", action: "show coordinate frame \(frame)", to: &commands, actions: &actions)
        }

        if containsAny(text, ["asymmetric unit", "original asymmetric", "show the asu", "show asu"]) {
            append("assembly asymmetric", action: "return to the asymmetric unit", to: &commands, actions: &actions)
        } else if let assembly = firstCapture(
            pattern: #"(?:show|build|open|display)?\s*(?:biological\s+)?assembly\s+([a-z0-9]+)"#,
            in: text
        ) {
            append("assembly \(assembly)", action: "build biological assembly \(assembly)", to: &commands, actions: &actions)
        }

        if containsAny(text, ["primary coordinates", "default coordinates", "primary conformation"]) {
            append("altloc primary", action: "show the primary atom coordinates", to: &commands, actions: &actions)
        } else if let alternate = firstCapture(
            pattern: #"(?:alternate\s+(?:location|conformation)|altloc)\s+([a-z0-9]+)"#,
            in: text
        ) {
            append("altloc \(alternate)", action: "show alternate location \(alternate.uppercased())", to: &commands, actions: &actions)
        }

        if commands.isEmpty, text == "help" || containsAny(text, ["what can you do", "show me the commands", "how do i use this"]) {
            append("help", action: "show the available commands", to: &commands, actions: &actions)
        }

        if commands.isEmpty, let directCommand = directCommand(from: text) {
            append(directCommand, action: "run `\(directCommand)`", to: &commands, actions: &actions)
        }

        guard !commands.isEmpty else {
            return CopilotPlan(
                commands: [],
                summary: "I can currently open PDB or EMDB entries, change representation and coloring, adjust the map contour, show or hide models, and clear selections."
            )
        }
        return CopilotPlan(commands: commands, summary: "I’ll \(joined(actions)).")
    }

    private func append(
        _ command: String,
        action: String,
        to commands: inout [String],
        actions: inout [String]
    ) {
        guard !commands.contains(command) else { return }
        commands.append(command)
        actions.append(action)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private func pdbIdentifier(in text: String) -> String? {
        firstCapture(pattern: #"\b([0-9][a-z0-9]{3})\b"#, in: text)?.lowercased()
    }

    private func emdbIdentifier(in text: String) -> String? {
        if let identifier = firstCapture(pattern: #"\bemd(?:b)?[- ]?([0-9]{4,6})\b"#, in: text) {
            return identifier
        }
        guard text.contains("emdb") || text.contains("density map") else { return nil }
        return firstCapture(pattern: #"\b([0-9]{4,6})\b"#, in: text)
    }

    private func contourLevel(in text: String) -> String? {
        let patterns = [
            #"(?:contour(?: level)?|threshold|surface level|map level)(?:\s+(?:to|at|of))?\s+(-?[0-9]+(?:\.[0-9]+)?)"#,
            #"(?:surface|map)(?:\s+(?:to|at))\s+(-?[0-9]+(?:\.[0-9]+)?)"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: text), Float(value) != nil { return value }
        }
        return nil
    }

    private func molecularSurfaceOpacity(in text: String) -> String? {
        firstCapture(
            pattern: #"(?:molecular\s+)?surface\s+(?:opacity|transparency)(?:\s+(?:to|at|of))?\s+([0-9]+(?:\.[0-9]+)?)"#,
            in: text
        )
    }

    private func molecularSurfaceProbe(in text: String) -> String? {
        firstCapture(
            pattern: #"(?:surface\s+)?probe(?:\s+radius)?(?:\s+(?:to|at|of))?\s+([0-9]+(?:\.[0-9]+)?)"#,
            in: text
        )
    }

    private func selectionCommand(in text: String) -> (command: String, action: String)? {
        guard firstCapture(pattern: #"\b(select|choose|highlight)\b"#, in: text) != nil else { return nil }
        if containsAny(text, ["ligand", "ligands"]) {
            return ("select ligand", "select the ligand atoms")
        }
        if containsAny(text, ["water", "waters", "solvent"]) {
            return ("select water", "select water molecules")
        }
        if let chain = firstCapture(
            pattern: #"(?:select|choose|highlight)(?:\s+(?:all|the))?(?:\s+atoms\s+in)?\s+chain\s+([a-z0-9]+)\b"#,
            in: text
        ) {
            return ("select chain \(chain)", "select chain \(chain.uppercased())")
        }
        if let residue = firstCapture(
            pattern: #"(?:select|choose|highlight)(?:\s+the)?\s+residue\s+(-?[0-9]+)\b"#,
            in: text
        ) {
            return ("select residue \(residue)", "select residue \(residue)")
        }
        if let residueName = firstCapture(
            pattern: #"(?:select|choose|highlight)(?:\s+all)?\s+(?:residue|residues)\s+([a-z]{3})\b"#,
            in: text
        ) {
            return ("select resname \(residueName)", "select \(residueName.uppercased()) residues")
        }

        let elements = [
            "hydrogen": "H", "carbon": "C", "nitrogen": "N", "oxygen": "O",
            "phosphorus": "P", "sulfur": "S", "sulphur": "S", "iron": "FE",
            "calcium": "CA", "magnesium": "MG", "zinc": "ZN"
        ]
        for (name, symbol) in elements where text.contains(name) {
            return ("select element \(symbol)", "select \(name) atoms")
        }
        if let symbol = firstCapture(
            pattern: #"(?:select|choose|highlight)(?:\s+all)?\s+(?:element\s+)?([a-z]{1,2})(?:\s+atoms?)?\b"#,
            in: text
        ), !["my", "the", "all"].contains(symbol) {
            return ("select element \(symbol)", "select element \(symbol.uppercased())")
        }
        if text == "select all" || containsAny(text, ["select all atoms", "select everything", "highlight everything"]) {
            return ("select all", "select all atoms")
        }
        return nil
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func firstTwoCaptures(pattern: String, in text: String) -> (String, String)? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 2,
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[firstRange]), String(text[secondRange]))
    }

    private func directCommand(from text: String) -> String? {
        let commandPatterns = [
            #"^(?:open|fetch)\s+(?:[0-9][a-z0-9]{3}|emd[-_]?\d{4,6})$"#,
            #"^alphafold\s+[a-z0-9]{6,12}(?:-\d+)?$"#,
            #"^blast(?:\s+protein)?$"#,
            #"^similar(?:\s+(?:current|[0-9][a-z0-9]{3}))?$"#,
            #"^foldseek$"#,
            #"^compute\s+(?:esmfold|openfold|boltz)$"#,
            #"^style\s+(?:ball|ball&stick|ballandstick|spacefill|spheres|sticks|cartoon|ribbon|backbone|nucleotide|nucleotides|glycan|glycans|thermal|ellipsoid|ellipsoids)$"#,
            #"^color\s+(?:element|chain|residue|mono|monochrome)$"#,
            #"^label\s+(?:none|off|selected|atoms|residues|chains)$"#,
            #"^lighting\s+(?:studio|soft|flat|dramatic)$"#,
            #"^view\s+(?:front|back|left|right|top|bottom)$"#,
            #"^(?:axes|scalebar|arrow)\s+(?:show|hide)$"#,
            #"^clip\s+(?:near|far)\s+[0-9]+(?:\.[0-9]+)?$"#,
            #"^surface\s+level\s+-?[0-9]+(?:\.[0-9]+)?$"#,
            #"^surface\s+(?:show|hide)$"#,
            #"^surface\s+style\s+(?:solid|mesh|dots)$"#,
            #"^surface\s+color\s+(?:uniform|element|chain|residue|bfactor|b-factor|charge)$"#,
            #"^surface\s+(?:opacity|probe)\s+[0-9]+(?:\.[0-9]+)?$"#,
            #"^map\s+style\s+(?:surface|isosurface|volume|solid|slices|slice)$"#,
            #"^map\s+(?:smooth|sharpen|zone)\s+[0-9]+(?:\.[0-9]+)?$"#,
            #"^map\s+(?:stats|segment|difference)$"#,
            #"^map\s+segment\s+-?[0-9]+(?:\.[0-9]+)?$"#,
            #"^map\s+reference\s+(?:set|save)$"#,
            #"^map\s+crop(?:\s+\d+){6}$"#,
            #"^fit\s+(?:map|maps|map-to-map|atoms|structure)$"#,
            #"^fit\s+map\s+(?:rotate|rigid)$"#,
            #"^(?:undo|redo|addh|hydrogens|charges|dockprep|minimize)$"#,
            #"^delete\s+(?:selected|selection|atoms)$"#,
            #"^bond\s+(?:add(?:\s+[123])?|delete)$"#,
            #"^mutate\s+[a-z]{3}$"#,
            #"^chain\s+rename(?:\s+to)?\s+\S+(?:\s+\S+)?$"#,
            #"^(?:atom\s+add|addatom)\s+[a-z]{1,2}(?:\s+-?[0-9]+(?:\.[0-9]+)?){3}$"#,
            #"^(?:torsion|rotamer)\s+-?[0-9]+(?:\.[0-9]+)?$"#,
            #"^tug(?:\s+-?[0-9]+(?:\.[0-9]+)?){3}$"#,
            #"^dock\s+analyze$"#,
            #"^model\s+(?:loops|gaps|reference|template)$"#,
            #"^trajectory\s+(?:play|pause|stop|next|previous|prev)$"#,
            #"^trajectory\s+frame\s+[0-9]+$"#,
            #"^assembly\s+(?:[a-z0-9]+|asymmetric|asu|none)$"#,
            #"^altloc\s+(?:[a-z0-9]+|primary|default|none)$"#,
            #"^(?:hbonds|hbond|contacts|clashes|cavities|cavity|interfaces|interface|sequence|conservation)$"#,
            #"^interactions\s+clear$"#,
            #"^pseudobond\s+(?:add(?:\s+[a-z0-9._-]+)?|clear)$"#,
            #"^annotate\s+(?:start|on|stop|off|clear)$"#,
            #"^measure\s+(?:area|surface|volume|centroid|center|axis|plane)$"#,
            #"^align\s+chains\s+\S+\s+\S+$"#,
            #"^reference\s+(?:set|save|clear)$"#,
            #"^(?:rmsd|match)\s+reference$"#,
            #"^rmsd\s+(?:trajectory|frame)$"#,
            #"^(?:show|hide)\s+(?:atoms|structure|model|map|surface|volume)$"#,
            #"^presentation\s+(?:start|on|show|stop|off|exit)$"#,
            #"^select\s+(?:all|clear|none|ligand|ligands|water|waters|solvent|chain\s+\S+|residue\s+\S+|resname\s+\S+|element\s+\S+|atom\s+\S+)$"#,
            #"^(?:clear|help)$"#
        ]
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in commandPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if expression.firstMatch(in: text, range: fullRange) != nil { return text }
        }
        return nil
    }

    private func joined(_ values: [String]) -> String {
        guard let last = values.last else { return "do that" }
        if values.count == 1 { return last }
        if values.count == 2 { return values[0] + " and " + last }
        return values.dropLast().joined(separator: ", ") + ", and " + last
    }
}
