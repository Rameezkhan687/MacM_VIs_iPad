import Foundation
import Testing
@testable import MoleculePadCore

@Suite struct PluginSystemTests {
    @Test func acceptsDeclarativeAllowListedPlugin() throws {
        let manifest = MoleculePadPluginManifest(
            id: "org.example.presentation",
            name: "Presentation Tools",
            version: "1.0.0",
            commands: [MoleculePadPluginCommand(
                id: "ribbon",
                title: "Clean ribbon",
                symbol: "sparkles",
                script: "style cartoon; color chain; label none"
            )]
        )
        let restored = try MoleculePadPluginLoader().decodeAndValidate(JSONEncoder().encode(manifest))
        #expect(restored.id == manifest.id)
        #expect(restored.commands.first?.script.contains("cartoon") == true)
    }

    @Test func rejectsExecutableOrUnknownCommands() throws {
        let manifest = MoleculePadPluginManifest(
            id: "org.example.unsafe",
            name: "Unsafe",
            version: "1",
            commands: [MoleculePadPluginCommand(
                id: "shell", title: "Shell", script: "rm everything"
            )]
        )
        let data = try JSONEncoder().encode(manifest)
        #expect(throws: MolecularError.self) { try MoleculePadPluginLoader().decodeAndValidate(data) }
    }
}
