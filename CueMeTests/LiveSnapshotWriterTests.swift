import XCTest
@testable import CueMe

final class LiveSnapshotWriterTests: XCTestCase {
    /// Live snapshots used to be written synchronously on the MainActor, which
    /// stalled audio routing. They are now queued, coalesced per note and always
    /// settled before the authoritative save at the end of a session.
    func testCoalescesBurstsAndKeepsTheNewestRecordPerNote() {
        let recorded = SavedSnapshots()
        let writer = LiveSnapshotWriter { recorded.store($0) }
        let id = UUID()

        for index in 1...50 {
            writer.submit(liveSnapshot(id: id, goal: "estado \(index)"))
        }
        writer.flush()

        let saved = recorded.snapshot()
        XCTAssertFalse(saved.isEmpty)
        XCTAssertLessThanOrEqual(saved.count, 50)
        XCTAssertEqual(saved.last?.id, id)
        XCTAssertEqual(saved.last?.goal, "estado 50")
    }

    func testFlushWaitsForQueuedWork() {
        let recorded = SavedSnapshots()
        let writer = LiveSnapshotWriter { recorded.store($0) }

        writer.submit(liveSnapshot(id: UUID(), goal: "único"))
        writer.flush()

        XCTAssertEqual(recorded.snapshot().count, 1)
    }

    private func liveSnapshot(id: UUID, goal: String) -> SessionRecord {
        SessionRecord(
            id: id,
            startedAt: Date(timeIntervalSince1970: 0),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: goal,
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )
    }
}

private final class SavedSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [SessionRecord] = []

    func store(_ record: SessionRecord) {
        lock.withLock { records.append(record) }
    }

    func snapshot() -> [SessionRecord] {
        lock.withLock { records }
    }
}
