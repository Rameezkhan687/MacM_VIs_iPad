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

        if containsAny(text, ["cartoon", "ribbon"]) {
            append("style cartoon", action: "show the structure as a cartoon", to: &commands, actions: &actions)
        } else if containsAny(text, ["ball and stick", "ball-and-stick", "balls and sticks"]) {
            append("style ball", action: "use ball-and-stick representation", to: &commands, actions: &actions)
        } else if containsAny(text, ["spacefill", "space fill", "space-filling", "space filling", "full spheres", "van der waals"]) {
            append("style spacefill", action: "use space-filling spheres", to: &commands, actions: &actions)
        } else if containsAny(text, ["backbone", "trace only"]) {
            append("style backbone", action: "show the backbone trace", to: &commands, actions: &actions)
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

        if let level = contourLevel(in: text) {
            append("surface level \(level)", action: "set the map contour to \(level)", to: &commands, actions: &actions)
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

        if containsAny(text, ["clear selection", "clear my selection", "clear the selection", "deselect", "select nothing", "remove selection"]) {
            append("select clear", action: "clear the selection", to: &commands, actions: &actions)
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

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func directCommand(from text: String) -> String? {
        let commandPatterns = [
            #"^(?:open|fetch)\s+(?:[0-9][a-z0-9]{3}|emd[-_]?\d{4,6})$"#,
            #"^style\s+(?:ball|ball&stick|ballandstick|spacefill|spheres|sticks|cartoon|ribbon|backbone)$"#,
            #"^color\s+(?:element|chain|residue|mono|monochrome)$"#,
            #"^surface\s+level\s+-?[0-9]+(?:\.[0-9]+)?$"#,
            #"^(?:show|hide)\s+(?:atoms|structure|model|map|surface|volume)$"#,
            #"^(?:clear|select clear|help)$"#
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
