import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CopilotWorkspaceContext: Codable, Equatable, Sendable {
    public var structureName: String?
    public var atomCount: Int
    public var chainIDs: [String]
    public var mapName: String?
    public var selectedAtomCount: Int

    public init(
        structureName: String? = nil,
        atomCount: Int = 0,
        chainIDs: [String] = [],
        mapName: String? = nil,
        selectedAtomCount: Int = 0
    ) {
        self.structureName = structureName
        self.atomCount = atomCount
        self.chainIDs = chainIDs
        self.mapName = mapName
        self.selectedAtomCount = selectedAtomCount
    }
}

public struct CopilotBackendRequest: Codable, Sendable {
    public let request: String
    public let context: CopilotWorkspaceContext
    public let supportedProtocolVersion: Int

    public init(request: String, context: CopilotWorkspaceContext, supportedProtocolVersion: Int = 1) {
        self.request = request
        self.context = context
        self.supportedProtocolVersion = supportedProtocolVersion
    }
}

public struct CopilotBackendResponse: Codable, Sendable {
    public let summary: String
    public let commands: [String]

    public init(summary: String, commands: [String]) {
        self.summary = summary
        self.commands = commands
    }
}

public struct CopilotBackendClient: Sendable {
    public init() {}

    public func plan(
        endpoint: URL,
        request: String,
        context: CopilotWorkspaceContext,
        bearerToken: String? = nil
    ) async throws -> CopilotPlan {
        guard isPermittedEndpoint(endpoint) else {
            throw MolecularError.network("Use an HTTPS Copilot endpoint, or localhost while developing.")
        }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 90)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(CopilotBackendRequest(request: request, context: context))
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MolecularError.network("The Copilot service returned an error.")
        }
        guard data.count <= 1_000_000 else {
            throw MolecularError.network("The Copilot response is too large.")
        }
        return try validated(JSONDecoder().decode(CopilotBackendResponse.self, from: data))
    }

    public func validated(_ response: CopilotBackendResponse) throws -> CopilotPlan {
        let summary = response.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 2_000,
              !response.commands.isEmpty, response.commands.count <= 50 else {
            throw MolecularError.network("The Copilot service returned an invalid plan.")
        }
        let interpreter = CopilotInterpreter()
        let commands = response.commands.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard commands.allSatisfy(interpreter.isAllowedCommand) else {
            throw MolecularError.network("The Copilot service proposed a command outside MoleculePad’s allow-list.")
        }
        return CopilotPlan(commands: commands, summary: summary)
    }

    private func isPermittedEndpoint(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        return url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
    }
}
