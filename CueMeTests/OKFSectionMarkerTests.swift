import XCTest
@testable import CueMe

final class OKFSectionMarkerTests: XCTestCase {

    // MARK: - AC1

    func testMissingSectionIsAbsentNotAnError() {
        let body = "# Title\n\nSome user body.\n\n<!-- cueme:takeaways -->\n- [ ] one thing"

        let result = OKFSectionMarkers.split(body)

        XCTAssertNil(result.sections[.minutes])
        XCTAssertNil(result.sections[.coach])
        XCTAssertEqual(result.sections[.takeaways], "- [ ] one thing")
        XCTAssertTrue(result.residual.isEmpty)
    }

    // MARK: - AC2

    func testUnknownMarkerRegionGoesToResidual() {
        let body = """
        # Title

        User body.

        <!-- cueme:takeaways -->
        - [ ] one thing

        <!-- cueme:mystery -->
        ## Apêndice

        Something a future format version wrote here.
        """

        let result = OKFSectionMarkers.split(body)

        XCTAssertEqual(result.sections[.takeaways], "- [ ] one thing\n")
        XCTAssertEqual(result.sections.count, 1, "the unknown marker must not produce a section entry")
        XCTAssertEqual(
            result.residual,
            "<!-- cueme:mystery -->\n## Apêndice\n\nSomething a future format version wrote here."
        )
    }

    // MARK: - AC2, continued: more than one unknown region

    func testMultipleUnknownRegionsAreConcatenatedInOrder() {
        let body = """
        # Title

        <!-- cueme:first-unknown -->
        alpha

        <!-- cueme:takeaways -->
        - [ ] one thing

        <!-- cueme:second-unknown -->
        omega
        """

        let result = OKFSectionMarkers.split(body)

        XCTAssertEqual(result.sections[.takeaways], "- [ ] one thing\n")
        XCTAssertEqual(
            result.residual,
            "<!-- cueme:first-unknown -->\nalpha\n\n<!-- cueme:second-unknown -->\nomega"
        )
    }

    // MARK: - AC1, continued: a hand-edited file may repeat a marker

    func testRepeatedSectionRegionsAreConcatenatedInOrder() {
        let body = """
        # Title

        <!-- cueme:takeaways -->
        - [ ] first

        <!-- cueme:decisions -->
        - a decision

        <!-- cueme:takeaways -->
        - [ ] second
        """

        let result = OKFSectionMarkers.split(body)

        XCTAssertEqual(result.sections.count, 2)
        XCTAssertEqual(result.sections[.decisions], "- a decision\n")
        XCTAssertEqual(result.sections[.takeaways], "- [ ] first\n\n- [ ] second")
    }

    // MARK: - AC3

    func testEscapeIsAnExactFixedPointIncludingRepeats() {
        let original = "before this line\n<!-- cueme:transcript -->\nafter this line"

        let escapedOnce = OKFSectionMarkers.escape(original)
        XCTAssertNotEqual(escapedOnce, original, "the marker-looking line must have been altered")
        XCTAssertEqual(OKFSectionMarkers.unescape(escapedOnce), original, "single round trip must be exact")

        // Escaping twice must not collapse back to a single backslash — each
        // application adds exactly one more level, and unescaping twice must
        // peel exactly those two levels back off, landing on the original.
        let escapedTwice = OKFSectionMarkers.escape(escapedOnce)
        XCTAssertNotEqual(escapedTwice, escapedOnce, "a second escape must add another level")
        XCTAssertEqual(
            OKFSectionMarkers.unescape(OKFSectionMarkers.unescape(escapedTwice)),
            original,
            "unescaping twice must undo escaping twice"
        )

        // A line that already carries the item-attribute comment form (no colon)
        // must be guarded the same way.
        let attributeLike = "<!--cueme {id: 1}-->text that looks like an attribute comment"
        let escapedAttribute = OKFSectionMarkers.escape(attributeLike)
        XCTAssertEqual(OKFSectionMarkers.unescape(escapedAttribute), attributeLike)
    }

    // MARK: - AC4

    func testParsesSectionsOutOfOrder() {
        let body = """
        # Title

        Body text.

        <!-- cueme:sources -->
        [^ev-1]: Some evidence.

        <!-- cueme:minutes -->
        ## Ata

        Overview text.

        <!-- cueme:takeaways -->
        - [ ] do the thing
        """

        let result = OKFSectionMarkers.split(body)

        XCTAssertEqual(result.sections[.sources], "[^ev-1]: Some evidence.\n")
        XCTAssertEqual(result.sections[.minutes], "## Ata\n\nOverview text.\n")
        XCTAssertEqual(result.sections[.takeaways], "- [ ] do the thing")
        XCTAssertTrue(result.residual.isEmpty)
    }

    // MARK: - AC5

    func testPlainNoteIsAllUserBody() {
        let body = "Just a plain note with no headers or markers at all.\n\nSecond paragraph."

        let result = OKFSectionMarkers.split(body)

        XCTAssertNil(result.h1)
        XCTAssertEqual(result.userBody, body)
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertTrue(result.residual.isEmpty)
    }

    // MARK: - AC6

    func testSplitsTheGoldenNoteBody() throws {
        let body = try Self.goldenNoteBody()

        let result = OKFSectionMarkers.split(body)

        XCTAssertEqual(result.h1, "Estratégia de frota elétrica")
        XCTAssertEqual(result.sections.count, 9)
        XCTAssertNil(result.sections[.transcript], "the golden note has no transcript section — that lives in raw/transcript.md")
        XCTAssertTrue(result.residual.isEmpty)

        for section in OKFSection.allCases where section != .transcript {
            XCTAssertNotNil(result.sections[section], "expected the golden note to carry a \(section.rawValue) section")
        }

        XCTAssertTrue(result.sections[.minutes]?.contains("## Ata") == true)
        XCTAssertTrue(result.sections[.minutes]?.contains("Mobilidade") == true)
        XCTAssertTrue(result.sections[.sources]?.contains("[^ev-e0000000-0000-4000-8000-000000000001]:") == true)
    }

    // MARK: - Fixture loading

    /// Reads `specs/okf-corpus/contracts/note.md` from disk relative to this test
    /// file's own location, and isolates everything after the frontmatter's
    /// closing `---` — i.e. the body `split(_:)` actually receives. `split` never
    /// sees frontmatter; that is `OKFFrontmatter`'s job (T003).
    private static func goldenNoteBody() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // CueMeTests/
            .deletingLastPathComponent() // repo root
        let goldenURL = repoRoot.appendingPathComponent("specs/okf-corpus/contracts/note.md")
        let markdown = try String(contentsOf: goldenURL, encoding: .utf8)

        let lines = markdown.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "---", "golden file must open with a frontmatter delimiter")
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            XCTFail("golden file must have a closing frontmatter delimiter")
            return ""
        }
        return lines[(closingIndex + 1)...].joined(separator: "\n")
    }
}
