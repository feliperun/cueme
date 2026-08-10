import XCTest
@testable import CueMe

/// AC1–AC5 (specs/okf-corpus/tasks/T012-note-reader.md). The two assertions
/// that matter for every fixture: byte idempotence of a second write, and
/// field-by-field fidelity of the reconstructed note against the original.
///
/// `MemoryNote` conforms to `Equatable` by `id` alone (constitution.md §4), so
/// every fidelity check here goes through `deepEqualFailures`, never
/// `XCTAssertEqual` on two `MemoryNote` values.
final class NoteDocumentRoundTripTests: XCTestCase {
    private static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("specs/okf-corpus/contracts/note.md")
    }

    /// Fields that structurally cannot round-trip through the OKF document,
    /// by design rather than by bug:
    ///
    /// `id` is deliberately *not* on this list: it round-trips through
    /// `x_cueme_id`. Chunk ids, the transcript's back-reference and UI
    /// selection all key on it, so a note may not change identity on reload.
    ///
    /// - `transcript` can never come back `.loaded`: this reader never reads
    ///   `raw/` (design.md §7), so it is always `.notLoaded(turns:)`.
    /// - `archiveFolderName` / `relativeFolderPath` are both derived from
    ///   `id` (`SessionArchive.folderName`) and are already marked for
    ///   deletion once the tree position replaces them (design.md §6).
    private static let fieldsExcludedFromRoundTrip: Set<String> = [
        "transcript", "archiveFolderName", "relativeFolderPath",
    ]

    private func assertRoundTripFidelity(
        _ got: MemoryNote,
        _ original: MemoryNote,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expected = original
        expected.transcript = .notLoaded(turns: original.transcript.turnCount)
        // `minutes.updatedAt` is never emitted (design.md §4.4): it is always
        // the max of the topics' own `updatedAt`, derived the same way on
        // both sides rather than round-tripped as an independent value.
        expected.minutes.updatedAt = expected.minutes.topics.map(\.updatedAt).max()
        for failure in deepEqualFailures(got, expected) where !Self.fieldsExcludedFromRoundTrip.contains(failure.field) {
            XCTFail(
                "MemoryNote.\(failure.field) differs:\n  got: \(failure.lhs)\n  original: \(failure.rhs)",
                file: file,
                line: line
            )
        }
    }

    private func assertByteIdempotent(
        _ rendered: String,
        _ read: MemoryNote,
        slug: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rewritten = NoteDocumentWriter.render(read, producer: "cueme/test")
        guard rewritten != rendered else { return }
        let dump = FileManager.default.temporaryDirectory.appendingPathComponent("okf-roundtrip-\(slug).md")
        try? rewritten.write(to: dump, atomically: true, encoding: .utf8)
        XCTFail("byte idempotence broke for \(slug); produzido em \(dump.path)", file: file, line: line)
    }

    private func assertRoundTrip(_ note: MemoryNote, slug: String, file: StaticString = #filePath, line: UInt = #line) {
        let rendered = NoteDocumentWriter.render(note, producer: "cueme/test")
        guard let read = NoteDocumentReader.parse(rendered, slug: slug, turns: note.transcript.turnCount) else {
            XCTFail("read returned nil for a document this writer just produced", file: file, line: line)
            return
        }

        assertByteIdempotent(rendered, read, slug: slug, file: file, line: line)
        assertRoundTripFidelity(read, note, file: file, line: line)
    }

    // MARK: - AC1 / AC2 — the four required fixtures

    func testRichNoteRoundTrips() {
        assertRoundTrip(RichNote.note, slug: "estrategia-de-frota-eletrica")
    }

    func testHandWrittenStyleNoteRoundTrips() {
        assertRoundTrip(NoteReaderFixtures.minimalNote, slug: "ideia-solta")
    }

    func testUnicodeEmojiAndRTLNoteRoundTrips() {
        assertRoundTrip(NoteReaderFixtures.unicodeNote, slug: "unicode")
    }

    func testLiteralMarkerLookalikeInBodyRoundTrips() {
        assertRoundTrip(NoteReaderFixtures.noteWithLiteralMarkerInBody, slug: "marcador-literal")
    }

    // MARK: - AC3

    func testGoldenFileReconstructsRichNoteWithDomainIDsPreserved() throws {
        let markdown = try String(contentsOf: Self.goldenURL, encoding: .utf8)
        let read = try XCTUnwrap(NoteDocumentReader.parse(markdown, slug: "estrategia-de-frota-eletrica", turns: 2))
        assertRoundTripFidelity(read, RichNote.note)

        // Domain ids embedded in the body/frontmatter must survive verbatim.
        XCTAssertEqual(read.coachCards.map(\.id), RichNote.note.coachCards.map(\.id))
        XCTAssertEqual(read.minutes.topics.map(\.id), RichNote.note.minutes.topics.map(\.id))
        XCTAssertEqual(read.takeaways.map(\.id), RichNote.note.takeaways.map(\.id))
        XCTAssertEqual(read.review.decisions.map(\.id), RichNote.note.review.decisions.map(\.id))
        XCTAssertEqual(read.review.openQuestions.map(\.id), RichNote.note.review.openQuestions.map(\.id))
        XCTAssertEqual(read.artifacts.map(\.id), RichNote.note.artifacts.map(\.id))
        XCTAssertEqual(read.attachments.map(\.id), RichNote.note.attachments.map(\.id))
        XCTAssertEqual(read.takeaways.flatMap(\.evidence).map(\.id), RichNote.note.takeaways.flatMap(\.evidence).map(\.id))
    }

    // MARK: - AC4

    func testReturnsNilWithoutFrontmatter() {
        XCTAssertNil(NoteDocumentReader.parse("# Só um título\n\nsem frontmatter nenhum.", slug: "sem-frontmatter", turns: 0))
    }

    func testReturnsNilWhenTypeIsEmpty() {
        let markdown = """
        ---
        type: ""
        title: Vazio
        ---

        # Vazio
        """
        XCTAssertNil(NoteDocumentReader.parse(markdown, slug: "vazio", turns: 0))
    }

    // MARK: - AC5

    func testHandWrittenNoteWithNoMarkersReturnsBodyTitleLabelsAndEmptyCollections() throws {
        let markdown = """
        ---
        type: Note
        title: Ideia solta
        tags:
          - pessoal
        ---

        # Ideia solta

        Só um pensamento sobre horários de reunião.
        """
        let note = try XCTUnwrap(NoteDocumentReader.parse(markdown, slug: "ideia-solta", turns: 0))

        XCTAssertEqual(note.displayTitle, "Ideia solta")
        XCTAssertEqual(note.markdownBody, "Só um pensamento sobre horários de reunião.")
        XCTAssertEqual(note.labels, ["pessoal"])

        XCTAssertEqual(note.transcript.turnCount, 0)
        XCTAssertTrue(note.takeaways.isEmpty)
        XCTAssertTrue(note.coachCards.isEmpty)
        XCTAssertTrue(note.notes.isEmpty)
        XCTAssertTrue(note.artifacts.isEmpty)
        XCTAssertTrue(note.attachments.isEmpty)
        XCTAssertTrue(note.links.isEmpty)
        XCTAssertTrue(note.coachFeedback.isEmpty)
        XCTAssertTrue(note.minutes.isEmpty)
        XCTAssertTrue(note.review.isEmpty)
        XCTAssertTrue(note.participantNames.isEmpty)
        XCTAssertEqual(note.residualMarkdown, "")
        XCTAssertEqual(note.unknownFrontmatterYAML, "")
    }
}
