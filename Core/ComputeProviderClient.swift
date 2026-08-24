import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MolecularComputeOperation: String, Codable, CaseIterable, Sendable {
    case foldseek
    case esmfold
    case openfold
    case boltz
}

public struct MolecularComputeRequest: Codable, Sendable {
    public let operation: MolecularComputeOperation
    public let sequence: String?
    public let pdb: String?
    public let protocolVersion: Int

    public init(operation: MolecularComputeOperation, sequence: String? = nil, pdb: String? = nil, protocolVersion: Int = 1) {
        self.operation = operation
        self.sequence = sequence
        self.pdb = pdb
        self.protocolVersion = protocolVersion
    }
}

public struct MolecularComputeResponse: Codable, Equatable, Sendable {
    public let summary: String
    public let resultText: String?
    public let structureURL: String?

    public init(summary: String, resultText: String? = nil, structureURL: String? = nil) {
        self.summary = summary
        self.resultText = resultText
        self.structureURL = structureURL
    }
}

public struct MolecularComputeClient: Sendable {
    public init() {}

    public func run(
        endpoint: URL,
        request value: MolecularComputeRequest,
        bearerToken: String? = nil
    ) async throws -> MolecularComputeResponse {
        guard permitted(endpoint) else {
            throw MolecularError.network("Use an HTTPS compute-provider endpoint, or localhost while developing.")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(value)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 5_000_000 else {
            throw MolecularError.network("The molecular compute provider returned an error.")
        }
        return try validated(JSONDecoder().decode(MolecularComputeResponse.self, from: data))
    }

    public func validated(_ value: MolecularComputeResponse) throws -> MolecularComputeResponse {
        let summary = value.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 4_000,
              (value.resultText?.count ?? 0) <= 1_000_000 else {
            throw MolecularError.network("The molecular compute provider returned an invalid result.")
        }
        if let location = value.structureURL {
            guard let url = URL(string: location), permitted(url) else {
                throw MolecularError.network("The provider returned an unsafe structure URL.")
            }
        }
        return MolecularComputeResponse(summary: summary, resultText: value.resultText, structureURL: value.structureURL)
    }

    private func permitted(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        return url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
    }
}
