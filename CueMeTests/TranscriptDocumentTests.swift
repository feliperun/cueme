import XCTest
@testable import CueMe

final class TranscriptDocumentTests: XCTestCase {
    private static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("specs/okf-corpus/contracts/transcript.md")
    }

    // MARK: - AC1

    func testNotLoadedLeavesTheFileByteIdentical() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("transcript.md")

        guard let initial = TranscriptDocument.render(RichNote.note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document for a loaded transcript")
        }
        try initial.write(to: fileURL, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: fileURL)

        var note = RichNote.note
        note.transcript = .notLoaded(turns: note.transcript.turnCount)
        let result = TranscriptDocument.render(note, producer: "cueme/test")

        XCTAssertNil(result, "a not-loaded transcript must never produce content to write")

        // The caller's contract is to skip the write entirely when `write`
        // returns nil. Simulate exactly that (do nothing) and prove the file
        // on disk never moved — bytes, not turn counts.
        let after = try Data(contentsOf: fileURL)
        XCTAssertEqual(before, after, "the file on disk must stay byte-identical when the transcript was never loaded")
    }

    // MARK: - AC2

    func testRoundTripsCorrectionAuditTrail() throws {
        guard let markdown = TranscriptDocument.render(RichNote.note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document")
        }

        let lines = TranscriptDocument.parse(markdown)
        guard let turn = lines.first(where: { $0.id == RichNote.turn2ID }) else {
            return XCTFail("turn 2 missing from round trip")
        }

        XCTAssertEqual(turn.text, "Vamos entregar no monorepo na sexta-feira.")
        XCTAssertEqual(turn.originalText, "Vamos entregar no mono rapo na sexta.")
        XCTAssertEqual(turn.editedAt, fixtureDate("2026-08-08T15:04:10.000Z"))
        XCTAssertEqual(turn.translation, "We will deliver on the monorepo on Friday.")
        XCTAssertEqual(turn.sourceTurnID, fixtureUUID("70000000-0000-4000-8000-0000000000ff"))
        XCTAssertTrue(turn.isFinal)
        XCTAssertTrue(turn.wasEdited)
    }

    // MARK: - AC3

    func testRoundTripsSixHundredTurns() throws {
        let base = fixtureDate("2026-08-08T14:30:11.000Z")
        let turns = (0..<600).map { index in
            TranscriptLine(
                id: UUID(),
                speaker: index.isMultiple(of: 2) ? .other : .self,
                text: "Turno número \(index).",
                isFinal: true,
                ts: base.addingTimeInterval(Double(index) * 0.001)
            )
        }
        var note = RichNote.note
        note.transcript = .loaded(turns)

        guard let markdown = TranscriptDocument.render(note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document")
        }
        let read = TranscriptDocument.parse(markdown)

        XCTAssertEqual(read.count, 600)
        let msFormatter = ISO8601DateFormatter.okfFixture
        for (produced, expected) in zip(read, turns) {
            XCTAssertEqual(produced.id, expected.id)
            XCTAssertEqual(msFormatter.string(from: produced.ts), msFormatter.string(from: expected.ts))
        }
    }

    // MARK: - AC4

    func testWritesTheGoldenTranscriptByteForByte() throws {
        let expected = try String(contentsOf: Self.goldenURL, encoding: .utf8)

        guard let produced = TranscriptDocument.render(RichNote.note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document for a loaded transcript")
        }

        if produced != expected {
            // Dumped so the whole document can be diffed against the golden;
            // the message below only points at the first divergence.
            let dump = FileManager.default.temporaryDirectory.appendingPathComponent("okf-transcript-produced.md")
            try? produced.write(to: dump, atomically: true, encoding: .utf8)
            XCTFail(firstLineDivergence(produced, expected) + "\ndocumento completo em \(dump.path)")
        }
    }

    // MARK: - AC5

    func testEscapesMarkerLookalikeInTurnText() throws {
        let literalText = "Primeira linha.\n<!--cueme:tr-->Isto não é uma tradução, é o que a pessoa disse."
        let line = TranscriptLine(
            id: fixtureUUID("70000000-0000-4000-8000-000000000099"),
            speaker: .other,
            text: literalText,
            isFinal: true,
            ts: fixtureDate("2026-08-08T14:32:00.000Z")
        )
        var note = RichNote.note
        note.transcript = .loaded([line])

        guard let markdown = TranscriptDocument.render(note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document")
        }

        XCTAssertTrue(
            markdown.contains("\\<!--cueme:tr-->Isto não é uma tradução"),
            "a literal marker-lookalike line inside turn text must be escaped on write"
        )
        XCTAssertFalse(
            markdown.contains("\n<!--cueme:tr-->Isto não é uma tradução"),
            "the marker-lookalike line must never appear unescaped"
        )

        let read = TranscriptDocument.parse(markdown)
        XCTAssertEqual(read.first?.text, literalText)
        XCTAssertNil(read.first?.translation, "the escaped lookalike line must not be parsed as a real translation marker")
    }

    // MARK: - AC6

    func testRenderTurnsMatchesFullRender() throws {
        let note = RichNote.note
        guard case .loaded(let turns) = note.transcript else {
            return XCTFail("fixture transcript should be loaded")
        }
        guard let full = TranscriptDocument.render(note, producer: "cueme/test") else {
            return XCTFail("expected a rendered document")
        }

        let turnsOnly = TranscriptDocument.renderTurnBlocks(
            turns,
            startedAt: note.audioTimelineStart,
            participantNames: note.participantNames
        )

        XCTAssertFalse(turnsOnly.isEmpty)
        XCTAssertTrue(
            full.hasSuffix(turnsOnly + "\n"),
            "write must end with exactly the same turn blocks renderTurns produces for the same lines"
        )
    }

    /// Comparing a hundred-byte document by eye is not viable; point at the
    /// first divergence.
    private func firstLineDivergence(_ produced: String, _ expected: String) -> String {
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
