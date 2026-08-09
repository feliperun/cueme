import Foundation
import XCTest
@testable import CueMe

/// Regression tests for `NoteItemAttributeCodec`, the inline `<!--cueme {…}-->`
/// comment codec. See `specs/okf-corpus/tasks/T005-item-attributes.md` for the
/// acceptance criteria (AC1-AC6) this file proves.
final class NoteItemAttributesTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_770_000_000) // 2026-02-02T02:40:00.000Z

    // MARK: - AC1: no comment -> whole text, empty attributes

    func testLineWithoutCommentKeepsFullText() {
        let line = "- [ ] Solicitar propostas aos fornecedores"

        let (text, attributes) = NoteItemAttributeCodec.decode(line)

        XCTAssertEqual(text, line)
        XCTAssertTrue(attributes.isEmpty)
    }

    // MARK: - AC2: "-->" inside the visible text must not truncate anything

    func testArrowInVisibleTextDoesNotTruncate() {
        let line = #"Compare A --> B before deciding <!--cueme {id: a0000000-0000-4000-8000-000000000001}-->"#

        let (text, attributes) = NoteItemAttributeCodec.decode(line)

        XCTAssertEqual(text, "Compare A --> B before deciding")
        XCTAssertEqual(attributes.uuid("id"), UUID(uuidString: "a0000000-0000-4000-8000-000000000001"))
    }

    /// The visible text may itself contain something that looks like an
    /// attribute comment — the line-start escape rule does not reach mid-line
    /// text, so this is reachable by hand-editing. Only the *last* opening
    /// token counts, and everything before it stays text.
    func testLiteralCommentInVisibleTextIsNotMistakenForTheAnchor() {
        let line = #"Escreva <!--cueme {exemplo}--> no corpo <!--cueme {id: a0000000-0000-4000-8000-000000000001}-->"#

        let (text, attributes) = NoteItemAttributeCodec.decode(line)

        XCTAssertEqual(text, #"Escreva <!--cueme {exemplo}--> no corpo"#)
        XCTAssertEqual(attributes.uuid("id"), UUID(uuidString: "a0000000-0000-4000-8000-000000000001"))
    }

    // MARK: - AC3: malformed comment degrades to plain text, never throws

    func testMalformedCommentDegradesToPlainText() {
        let unbalancedBraces = "- item <!--cueme {id: a0000000-0000-4000-8000-000000000001-->"
        let notYAML = "- item <!--cueme {this is not: [valid-->"
        let missingOpenBrace = "- item <!--cueme id: 1}-->"

        for line in [unbalancedBraces, notYAML, missingOpenBrace] {
            let (text, attributes) = NoteItemAttributeCodec.decode(line)
            XCTAssertEqual(text, line, "malformed comment must leave the whole line as text: \(line)")
            XCTAssertTrue(attributes.isEmpty, "malformed comment must yield empty attributes: \(line)")
        }
    }

    // MARK: - AC4: a requested attribute that does not exist is nil, no error

    func testMissingAttributeIsNil() {
        let line = "- item <!--cueme {id: a0000000-0000-4000-8000-000000000001}-->"

        let (_, attributes) = NoteItemAttributeCodec.decode(line)

        // The present key must resolve correctly, so this test cannot pass
        // vacuously against an implementation that returns nil for everything.
        XCTAssertEqual(attributes.uuid("id"), UUID(uuidString: "a0000000-0000-4000-8000-000000000001"))

        XCTAssertNil(attributes["assignee"])
        XCTAssertNil(attributes.string("assignee"))
        XCTAssertNil(attributes.date("due"))
        XCTAssertNil(attributes.double("confidence"))
        XCTAssertNil(attributes.strings("keyterms"))
        XCTAssertNil(attributes.uuid("supersedes"))
    }

    // MARK: - AC5: encode -> decode round-trips typed values, including a
    // list of strings and a date

    func testRoundTripsTypedValues() {
        let id = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
        let pairs: [(String, OKFValue)] = [
            ("id", .string(id.uuidString)),
            ("at", .date(fixedDate)),
            ("confidence", .double(0.94)),
            ("assignee", .string("Marina")),
            ("keyterms", .array([.string("fleet"), .string("TCO")])),
        ]

        let comment = NoteItemAttributeCodec.encode(pairs)
        let line = "- [ ] Solicitar propostas" + comment
        let (text, attributes) = NoteItemAttributeCodec.decode(line)

        XCTAssertEqual(text, "- [ ] Solicitar propostas")
        XCTAssertEqual(attributes.uuid("id"), id)
        XCTAssertEqual(attributes.date("at"), fixedDate)
        XCTAssertEqual(attributes.double("confidence"), 0.94)
        XCTAssertEqual(attributes.string("assignee"), "Marina")
        XCTAssertEqual(attributes.strings("keyterms"), ["fleet", "TCO"])
    }

    func testEncodeOfEmptyPairsIsEmptyString() {
        XCTAssertEqual(NoteItemAttributeCodec.encode([]), "")
    }

    func testEncodeFormatMatchesExactSpacing() {
        let pairs: [(String, OKFValue)] = [("id", .string("a0000000-0000-4000-8000-000000000001"))]

        let comment = NoteItemAttributeCodec.encode(pairs)

        XCTAssertEqual(comment, " <!--cueme {id: a0000000-0000-4000-8000-000000000001}-->")
    }

    // MARK: - AC6: every anchor line in the golden note decodes an `id`

    func testDecodesEveryAnchorInTheGoldenNote() throws {
        let markdown = try String(contentsOf: Self.goldenNoteURL, encoding: .utf8)
        let anchorLines = markdown
            .components(separatedBy: "\n")
            .filter { $0.contains("<!--cueme {") }

        XCTAssertEqual(anchorLines.count, 8, "expected 8 item-attribute anchors in the golden note")

        for line in anchorLines {
            let (_, attributes) = NoteItemAttributeCodec.decode(line)
            XCTAssertNotNil(attributes.uuid("id"), "expected a parsed `id` for anchor line: \(line)")
        }
    }

    // MARK: - Fixture helpers

    private static var goldenNoteURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CueMeTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("specs/okf-corpus/contracts/note.md")
    }
}
