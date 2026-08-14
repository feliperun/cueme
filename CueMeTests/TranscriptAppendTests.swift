import XCTest
@testable import CueMe

/// `CorpusStore.appendTranscript` writes new turns onto `raw/transcript.md`
/// without rewriting what is already there. The invariant that lets it exist:
/// N appends produce exactly the bytes one full render would.
final class TranscriptAppendTests: XCTestCase {
    private var corpus: URL!

    override func setUpWithError() throws {
        corpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeAppend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        CorpusStore.rootOverride = corpus
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: corpus)
        corpus = nil
    }

    /// AC3 — the invariant that lets the append exist at all: N appends produce
    /// exactly the bytes one full render of the same N turns would.
    func testAppendedFileMatchesFullRender() throws {
        var note = liveNoteOnDisk()
        let turns = (1...12).map { index in
            TranscriptLine(
                speaker: index.isMultiple(of: 2) ? .other : .`self`,
                text: "turno \(index)",
                isFinal: true,
                ts: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        // Appended a few at a time, the way a live session produces them.
        for chunk in stride(from: 0, to: turns.count, by: 3) {
            CorpusStore.appendTranscript(Array(turns[chunk..<min(chunk + 3, turns.count)]), to: note)
        }
        let appended = try String(contentsOf: transcriptFileURL(note), encoding: .utf8)

        note.transcript = .loaded(turns)
        let rendered = try XCTUnwrap(TranscriptDocument.render(note))

        XCTAssertEqual(appended, rendered)
        XCTAssertEqual(TranscriptDocument.parse(appended).map(\.text), turns.map(\.text))
    }

    /// AC5 — appending never needs the old turns in memory, which is what makes
    /// a lazily-loaded transcript safe to write to.
    func testAppendWorksWithUnloadedTranscript() throws {
        var note = liveNoteOnDisk()
        let existing = (1...3).map {
            TranscriptLine(speaker: .other, text: "antigo \($0)", isFinal: true, ts: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        CorpusStore.appendTranscript(existing, to: note)

        note.transcript = .notLoaded(turns: existing.count)
        let fresh = TranscriptLine(speaker: .`self`, text: "novo", isFinal: true, ts: Date(timeIntervalSince1970: 9))
        let written = CorpusStore.appendTranscript([fresh], to: note)

        XCTAssertEqual(written, [fresh.id])
        XCTAssertEqual(
            TranscriptDocument.parse(try String(contentsOf: transcriptFileURL(note), encoding: .utf8)).map(\.text),
            ["antigo 1", "antigo 2", "antigo 3", "novo"],
            "the old turns were never in memory and must still be on disk, in order"
        )
    }

    /// A live snapshot must not re-render the transcript — that is the cost this
    /// task removes. It also must not erase what the appends put there.
    func testLiveSaveLeavesTheTranscriptFileAlone() throws {
        var note = liveNoteOnDisk()
        let turns = [TranscriptLine(speaker: .other, text: "único", isFinal: true, ts: Date(timeIntervalSince1970: 1))]
        CorpusStore.appendTranscript(turns, to: note)
        let before = try String(contentsOf: transcriptFileURL(note), encoding: .utf8)

        note.transcript = .loaded([])
        CorpusStore.save(note, includingTranscript: false)

        XCTAssertEqual(try String(contentsOf: transcriptFileURL(note), encoding: .utf8), before)
    }

    private func makeLiveCorpus() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeLive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
        return root
    }

    private func teardownLiveCorpus(_ root: URL) {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func liveNoteOnDisk() -> MemoryNote {
        var note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            displayTitle: "Sessão ao vivo",
            titleSource: .user
        )
        note = CorpusStore.resolvingLocation(note)
        CorpusStore.save(note)
        return note
    }

    private func transcriptFileURL(_ note: MemoryNote) -> URL {
        CorpusStore.noteFolder(for: note).appendingPathComponent(OKFBundle.transcriptRelativePath)
    }
}
