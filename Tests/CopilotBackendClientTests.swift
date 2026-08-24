import Testing
@testable import MoleculePadCore

@Suite struct CopilotBackendClientTests {
    @Test func validatesTypedAllowListedPlans() throws {
        let response = CopilotBackendResponse(
            summary: "I’ll show a chain-colored cartoon.",
            commands: ["style cartoon", "color chain"]
        )
        let plan = try CopilotBackendClient().validated(response)
        #expect(plan.commands == response.commands)
        #expect(plan.isActionable)
    }

    @Test func rejectsCommandsOutsideBoundary() {
        let response = CopilotBackendResponse(summary: "Unsafe", commands: ["launch shell"])
        #expect(throws: MolecularError.self) { try CopilotBackendClient().validated(response) }
    }
}
