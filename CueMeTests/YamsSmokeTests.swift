import XCTest
import Yams

private struct Generated: Codable, Equatable {
    let by: String
    let at: String
}

private struct SourceRef: Codable, Equatable {
    let id: String
    let resource: String
}

private struct Frontmatter: Codable, Equatable {
    let generated: Generated
    let sources: [SourceRef]
}

final class YamsSmokeTests: XCTestCase {
    func testYamsDecodesNestedMappingsAndSequences() throws {
        let yaml = """
        generated:
          by: "cueme/1.0"
          at: "2026-08-08T14:30:11.000Z"
        sources:
          - id: "ev-1"
            resource: "raw/transcript.md#t-1"
          - id: "ev-2"
            resource: "raw/transcript.md#t-2"

        """

        let decoded = try YAMLDecoder().decode(Frontmatter.self, from: yaml)

        XCTAssertEqual(decoded.generated, Generated(by: "cueme/1.0", at: "2026-08-08T14:30:11.000Z"))
        XCTAssertEqual(decoded.sources, [
            SourceRef(id: "ev-1", resource: "raw/transcript.md#t-1"),
            SourceRef(id: "ev-2", resource: "raw/transcript.md#t-2"),
        ])

        // Re-emit and decode again: proves the nested mapping + list of mappings
        // round-trips through Yams without structural loss.
        let reemitted = try YAMLEncoder().encode(decoded)
        let redecoded = try YAMLDecoder().decode(Frontmatter.self, from: reemitted)

        XCTAssertEqual(redecoded, decoded)
    }
}
