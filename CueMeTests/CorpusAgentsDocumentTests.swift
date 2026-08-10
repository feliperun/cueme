import XCTest
@testable import CueMe

/// The corpus `AGENTS.md` is the schema that travels with the folder. It is
/// written once and then belongs to the user.
final class CorpusAgentsDocumentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeAgents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private var url: URL { root.appendingPathComponent("AGENTS.md") }

    // MARK: AC2 — never overwritten

    func testExistingAgentsFileIsNeverOverwritten() throws {
        let edited = "# Meu schema\n\nRegras que eu escrevi.\n"
        try edited.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertFalse(CorpusStore.writeAgentsFileIfAbsent(), "it already exists")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), edited)
    }

    func testAbsentAgentsFileIsWrittenOnce() throws {
        XCTAssertTrue(CorpusStore.writeAgentsFileIfAbsent())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), CorpusAgentsDocument.content)
        XCTAssertFalse(CorpusStore.writeAgentsFileIfAbsent(), "a second call must be a no-op")
    }

    /// The golden in `specs/okf-corpus/contracts/corpus-agents.md` is the
    /// contract. If the file the app writes drifts from it, the contract has to
    /// change first — not the other way around.
    func testWrittenContentMatchesTheGolden() throws {
        let golden = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("specs/okf-corpus/contracts/corpus-agents.md"),
            encoding: .utf8
        )
        let fenced = golden.components(separatedBy: "```markdown\n")
        let body = try XCTUnwrap(fenced.count > 1 ? fenced[1] : nil)
        let close = try XCTUnwrap(body.range(of: "\n```"))
        let expected = String(body[body.startIndex..<close.lowerBound]) + "\n"

        XCTAssertEqual(CorpusAgentsDocument.content, expected)
    }

    func testTheAgentsFileIsNotPartOfTheBundle() throws {
        CorpusStore.writeAgentsFileIfAbsent()

        XCTAssertFalse(
            CorpusAgentsDocument.content.hasPrefix("---"),
            "it carries no frontmatter — it is not an OKF document"
        )
        XCTAssertTrue(
            CorpusStore.loadNotes().isEmpty,
            "and the tree loader must not mistake it for a note"
        )
    }
}
