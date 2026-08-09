import XCTest
@testable import CueMe

final class NoteDocumentWriterTests: XCTestCase {
    private static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("specs/okf-corpus/contracts/note.md")
    }

    private func plainNote() -> MemoryNote {
        MemoryNote(
            id: fixtureUUID("22222222-2222-4222-8222-222222222222"),
            startedAt: RichNote.startedAt,
            endedAt: RichNote.startedAt,
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: "Ideia solta",
            noteKind: .note,
            markdownBody: "Só um pensamento.",
            titleSource: .user,
            modifiedAt: RichNote.modifiedAt
        )
    }

    // MARK: - AC1

    func testWritesTheGoldenNoteByteForByte() throws {
        let expected = try String(contentsOf: Self.goldenURL, encoding: .utf8)

        let produced = NoteDocumentWriter.render(RichNote.note, producer: "cueme/test")

        if produced != expected {
            // Dumped so the whole document can be diffed against the golden;
            // the message below only points at the first divergence.
            let dump = FileManager.default.temporaryDirectory.appendingPathComponent("okf-produced.md")
            try? produced.write(to: dump, atomically: true, encoding: .utf8)
            XCTFail(firstDifference(produced, expected) + "\ndocumento completo em \(dump.path)")
        }
    }

    // MARK: - AC2

    func testEmitsTurnCountWithoutLoadingTheTranscript() {
        var note = RichNote.note
        note.transcript = .notLoaded(turns: 214)

        let produced = NoteDocumentWriter.render(note, producer: "cueme/test")

        XCTAssertTrue(produced.contains("x_cueme_transcript:\n  file: \"raw/transcript.md\"\n  turns: 214"))
    }

    // MARK: - AC3

    func testPlainNoteHasNoMachineMarkers() {
        let produced = NoteDocumentWriter.render(plainNote(), producer: "cueme/test")

        XCTAssertFalse(produced.contains("cueme:"), "a hand-written note must carry no machine markers")
        XCTAssertTrue(produced.contains("# Ideia solta"))
        XCTAssertTrue(produced.contains("Só um pensamento."))
    }

    // MARK: - AC4

    func testOmitsEmptyOptionalKeys() {
        let produced = NoteDocumentWriter.render(plainNote(), producer: "cueme/test")

        for key in [
            "description", "tags", "sources", "x_cueme_links", "x_cueme_models",
            "x_cueme_audio", "x_cueme_transcript", "x_cueme_attachments",
            "x_cueme_vocabulary", "x_cueme_coach_feedback"
        ] {
            XCTAssertFalse(produced.contains("\(key):"), "\(key) must be omitted, not emitted empty or null")
        }
        XCTAssertFalse(produced.contains("null"))
    }

    // MARK: - AC5

    func testReemitsUnknownFrontmatterLast() {
        var note = plainNote()
        note.unknownFrontmatterYAML = "custom_key: valor\nx_outra_ferramenta:\n  campo: 1"

        let produced = NoteDocumentWriter.render(note, producer: "cueme/test")
        let frontmatter = produced.components(separatedBy: "---")[1]

        XCTAssertTrue(frontmatter.contains("custom_key: valor"))
        XCTAssertTrue(frontmatter.contains("x_outra_ferramenta:\n  campo: 1"))
        let lastKnown = try? XCTUnwrap(frontmatter.range(of: "x_cueme_integrity:"))
        let unknown = try? XCTUnwrap(frontmatter.range(of: "custom_key:"))
        if let lastKnown, let unknown {
            XCTAssertTrue(lastKnown.lowerBound < unknown.lowerBound, "unknown keys come after known ones")
        }
    }

    // MARK: - AC6

    func testReemitsResidualAtTheEnd() {
        var note = plainNote()
        note.residualMarkdown = "## Apêndice\n\nAlgo que o usuário escreveu no fim."

        let produced = NoteDocumentWriter.render(note, producer: "cueme/test")

        XCTAssertTrue(produced.hasSuffix("## Apêndice\n\nAlgo que o usuário escreveu no fim.\n"))
    }

    // MARK: - AC7

    func testEscapesMarkerLookalikesInFreeText() {
        var note = plainNote()
        note.markdownBody = "Exemplo:\n<!-- cueme:minutes -->\nfim."

        let produced = NoteDocumentWriter.render(note, producer: "cueme/test")

        XCTAssertTrue(produced.contains("\\<!-- cueme:minutes -->"))
        XCTAssertFalse(produced.contains("\n<!-- cueme:minutes -->"))
    }

    // MARK: - AC8

    func testWritingTwiceIsByteIdentical() {
        let first = NoteDocumentWriter.render(RichNote.note, producer: "cueme/test")
        let second = NoteDocumentWriter.render(RichNote.note, producer: "cueme/test")

        XCTAssertEqual(first, second)
    }

    /// Comparing 120 lines by eye is not viable; point at the first divergence.
    private func firstDifference(_ produced: String, _ expected: String) -> String {
        let a = produced.components(separatedBy: "\n")
        let b = expected.components(separatedBy: "\n")
        for index in 0..<max(a.count, b.count) where index >= min(a.count, b.count) || a[index] != b[index] {
            let got = index < a.count ? a[index] : "<sem linha>"
            let want = index < b.count ? b[index] : "<sem linha>"
            return "linha \(index + 1) difere:\n  produzido: |\(got)|\n  golden:    |\(want)|"
        }
        return "conteúdo igual mas comprimentos diferem: \(a.count) vs \(b.count) linhas"
    }
}
