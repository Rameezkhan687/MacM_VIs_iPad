import Foundation

/// Declarative, App-Store-safe extension format. Plug-ins contribute named buttons
/// that invoke the same allow-listed commands used by Copilot; no executable code
/// or credentials are loaded into the app.
public struct MoleculePadPluginCommand: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String?
    public let script: String

    public init(id: String, title: String, symbol: String? = nil, script: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.script = script
    }
}

public struct MoleculePadPluginManifest: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let commands: [MoleculePadPluginCommand]

    public init(
        id: String,
        name: String,
        version: String,
        author: String? = nil,
        commands: [MoleculePadPluginCommand]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.commands = commands
    }
}

public struct MoleculePadQuickCommand: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var script: String

    public init(id: UUID = UUID(), title: String, script: String) {
        self.id = id
        self.title = title
        self.script = script
    }
}

public struct MoleculePadPluginLoader: Sendable {
    public init() {}

    public func decodeAndValidate(_ data: Data) throws -> MoleculePadPluginManifest {
        guard data.count <= 1_000_000 else {
            throw MolecularError.invalidStructure("Plug-in manifests must be smaller than 1 MB.")
        }
        let manifest = try JSONDecoder().decode(MoleculePadPluginManifest.self, from: data)
        let identifierPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$"#
        guard manifest.id.range(of: identifierPattern, options: .regularExpression) != nil,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.version.isEmpty,
              (1...64).contains(manifest.commands.count) else {
            throw MolecularError.invalidStructure("The plug-in manifest has invalid identity or command metadata.")
        }
        let interpreter = CopilotInterpreter()
        var commandIDs = Set<String>()
        for command in manifest.commands {
            guard command.id.range(of: identifierPattern, options: .regularExpression) != nil,
                  commandIDs.insert(command.id).inserted,
                  !command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  command.script.count <= 8_000 else {
                throw MolecularError.invalidStructure("The plug-in contains an invalid or duplicate command.")
            }
            let statements = Self.statements(in: command.script)
            guard !statements.isEmpty, statements.count <= 50,
                  statements.allSatisfy(interpreter.isAllowedCommand) else {
                throw MolecularError.invalidStructure(
                    "Plug-in command \(command.title) contains an operation that is not on MoleculePad’s allow-list."
                )
            }
        }
        return manifest
    }

    public static func statements(in script: String) -> [String] {
        script
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
