import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RCSBStructureSearchHit: Codable, Equatable, Sendable {
    public let identifier: String
    public let score: Double?
}

public struct RCSBStructureSearchClient: Sendable {
    public init() {}

    public func requestBody(pdbID rawID: String, assemblyID: String = "1", rows: Int = 25) throws -> Data {
        let pdbID = rawID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard pdbID.range(of: #"^[0-9][A-Z0-9]{3}$"#, options: .regularExpression) != nil else {
            throw MolecularError.network("A four-character deposited PDB ID is required for 3D similarity search.")
        }
        let payload: [String: Any] = [
            "query": [
                "type": "terminal",
                "service": "structure",
                "parameters": [
                    "value": ["entry_id": pdbID, "assembly_id": assemblyID],
                    "number_of_candidates": 2_000
                ]
            ],
            "return_type": "assembly",
            "request_options": [
                "paginate": ["start": 0, "rows": min(100, max(1, rows))],
                "scoring_strategy": "structure",
                "results_verbosity": "minimal"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public func search(pdbID: String, assemblyID: String = "1", rows: Int = 25) async throws -> [RCSBStructureSearchHit] {
        guard let endpoint = URL(string: "https://search.rcsb.org/rcsbsearch/v2/query") else { return [] }
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try requestBody(pdbID: pdbID, assemblyID: assemblyID, rows: rows)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MolecularError.network("RCSB returned an invalid response.")
        }
        if http.statusCode == 204 { return [] }
        guard (200..<300).contains(http.statusCode), data.count <= 5_000_000 else {
            throw MolecularError.network("RCSB structure search failed.")
        }
        return try decodeResponse(data)
    }

    public func decodeResponse(_ data: Data) throws -> [RCSBStructureSearchHit] {
        struct Response: Decodable {
            struct Item: Decodable { let identifier: String; let score: Double? }
            let result_set: [Item]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.result_set ?? []).map { RCSBStructureSearchHit(identifier: $0.identifier, score: $0.score) }
    }
}
