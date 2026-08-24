import Foundation
import Testing
@testable import MoleculePadCore

@Suite struct RCSBSearchClientTests {
    @Test func buildsOfficialStructureServiceQuery() throws {
        let data = try RCSBStructureSearchClient().requestBody(pdbID: "1crn")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let query = try #require(json["query"] as? [String: Any])
        #expect(query["service"] as? String == "structure")
        let parameters = try #require(query["parameters"] as? [String: Any])
        let value = try #require(parameters["value"] as? [String: Any])
        #expect(value["entry_id"] as? String == "1CRN")
    }

    @Test func decodesRankedIdentifiers() throws {
        let data = Data(#"{"result_set":[{"identifier":"1ABC-1","score":0.93},{"identifier":"2XYZ-1","score":0.8}]}"#.utf8)
        let hits = try RCSBStructureSearchClient().decodeResponse(data)
        #expect(hits.map(\.identifier) == ["1ABC-1", "2XYZ-1"])
    }
}
