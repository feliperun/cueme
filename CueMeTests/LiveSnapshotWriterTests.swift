import XCTest
@testable import CueMe

final class LiveSnapshotWriterTests: XCTestCase {
    /// Live snapshots used to be written synchronously on the MainActor, which
    /// stalled audio routing. They are now queued, coalesced per note and always
    /// settled before the authoritative save at the end of a session.
    func testCoalescesBurstsAndKeepsTheNewestRecordPerNote() {
        let recorded = SavedSnapshots()
        let writer = LiveSnapshotWriter { recorded.recordBatch($0) }
        let id = UUID()

        for index in 1...50 {
            writer.submit(liveNote(id: id, goal: "estado \(index)"))
        }
        writer.flush()

        let saved = recorded.savedRecords()
        XCTAssertFalse(saved.isEmpty)
        XCTAssertLessThanOrEqual(saved.count, 50)
        XCTAssertEqual(saved.last?.id, id)
        XCTAssertEqual(saved.last?.goal, "estado 50")
    }

    func testFlushWaitsForQueuedWork() {
        let recorded = SavedSnapshots()
        let writer = LiveSnapshotWriter { recorded.recordBatch($0) }

        writer.submit(liveNote(id: UUID(), goal: "único"))
        writer.flush()

        XCTAssertEqual(recorded.savedRecords().count, 1)
    }

    // MARK: - Incremental transcript

    /// AC1 — a drain writes the new turn and nothing else. Counted through a
    /// spy, never timed.
    func testAppendWritesOnlyTheNewTurn() {
        let appends = AppendedTurns()
        let writer = LiveSnapshotWriter(save: { _ in }, appendTranscript: { lines, _ in appends.recordBatch(lines) })
        let id = UUID()
        let first = finalTurn("primeiro")
        let second = finalTurn("segundo")

        writer.submit(liveNote(id: id, goal: "g", turns: [first]))
        writer.flush()
        writer.submit(liveNote(id: id, goal: "g", turns: [first, second]))
        writer.flush()

        XCTAssertEqual(appends.recordedBatches().map { $0.map(\.text) }, [["primeiro"], ["segundo"]])
    }

    /// AC6 — the same turns submitted again write nothing.
    func testConsecutiveAppendsDoNotDuplicate() {
        let appends = AppendedTurns()
        let writer = LiveSnapshotWriter(save: { _ in }, appendTranscript: { lines, _ in appends.recordBatch(lines) })
        let id = UUID()
        let turns = [finalTurn("um"), finalTurn("dois")]

        for _ in 1...5 {
            writer.submit(liveNote(id: id, goal: "g", turns: turns))
            writer.flush()
        }

        XCTAssertEqual(appends.recordedBatches().count, 1)
        XCTAssertEqual(appends.recordedBatches().first?.map(\.text), ["um", "dois"])
    }

    /// A partial turn is not durable — only finals reach the file.
    func testPartialTurnsAreNeverAppended() {
        let appends = AppendedTurns()
        let writer = LiveSnapshotWriter(save: { _ in }, appendTranscript: { lines, _ in appends.recordBatch(lines) })
        let partial = TranscriptLine(speaker: .other, text: "meio…", isFinal: false, ts: Date(timeIntervalSince1970: 5))

        writer.submit(liveNote(id: UUID(), goal: "g", turns: [partial]))
        writer.flush()

        XCTAssertTrue(appends.recordedBatches().isEmpty)
    }

    /// A store that refuses the write must not be recorded as having written:
    /// the *same* writer has to offer the turn again on the next drain. One
    /// instance, so the retry really depends on trusting the store's answer.
    func testATurnRefusedByTheStoreIsRetriedByTheSameWriter() {
        let appends = AppendedTurns()
        let writer = LiveSnapshotWriter(save: { _ in }, appendTranscript: { lines, _ in
            appends.recordBatchRefusingFirst(lines)
        })
        let id = UUID()
        let only = finalTurn("um")

        writer.submit(liveNote(id: id, goal: "g", turns: [only]))
        writer.flush()
        writer.submit(liveNote(id: id, goal: "g", turns: [only]))
        writer.flush()

        XCTAssertEqual(
            appends.recordedBatches().map { $0.map(\.text) },
            [["um"], ["um"]],
            "a turn recorded as written before the store confirmed it would be lost"
        )
    }

    private func finalTurn(_ text: String) -> TranscriptLine {
        TranscriptLine(speaker: .other, text: text, isFinal: true, ts: Date(timeIntervalSince1970: 5))
    }

    private func liveNote(id: UUID, goal: String, turns: [TranscriptLine]) -> MemoryNote {
        var note = liveNote(id: id, goal: goal)
        note.transcript = .loaded(turns)
        return note
    }

    private func liveNote(id: UUID, goal: String) -> MemoryNote {
        MemoryNote(
            id: id,
            startedAt: Date(timeIntervalSince1970: 0),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: goal,
            transcript: [],
            coachCards: [],
        )
    }
}

private final class AppendedTurns: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[TranscriptLine]] = []

    func recordBatch(_ lines: [TranscriptLine]) -> [UUID] {
        lock.withLock { recorded.append(lines) }
        return lines.map(\.id)
    }

    /// Refuses the first batch and accepts every later one, so a writer that
    /// marks a refused write as done is caught.
    func recordBatchRefusingFirst(_ lines: [TranscriptLine]) -> [UUID] {
        let isFirst = lock.withLock { () -> Bool in
            recorded.append(lines)
            return recorded.count == 1
        }
        return isFirst ? [] : lines.map(\.id)
    }

    func recordedBatches() -> [[TranscriptLine]] {
        lock.withLock { recorded }
    }
}

private final class SavedSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [MemoryNote] = []

    func recordBatch(_ record: MemoryNote) {
        lock.withLock { records.append(record) }
    }

    func savedRecords() -> [MemoryNote] {
        lock.withLock { records }
    }
}
