import Foundation

/// Serializes live archive snapshots away from the MainActor and coalesces bursts
/// to the newest record. `flush()` is used only at session shutdown so the final
/// authoritative save cannot be overwritten by an older queued snapshot.
///
/// The note's own `.md` is re-rendered whole — it is small now that the
/// transcript lives in `raw/transcript.md`. The transcript is not: each drain
/// appends only the turns it has not written yet, so an hour-long meeting does
/// not re-render hundreds of turns every few seconds.
final class LiveSnapshotWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CueMe.LiveSnapshotWriter", qos: .utility)
    private let lock = NSLock()
    private var pending: [UUID: MemoryNote] = [:]
    private var drainScheduled = false
    /// Turn ids already on disk, per note. This is what makes a second drain
    /// neither duplicate a turn nor skip one.
    private var appended: [UUID: Set<UUID>] = [:]
    private let save: @Sendable (MemoryNote) -> Void
    private let appendTranscript: @Sendable ([TranscriptLine], MemoryNote) -> [UUID]

    init(
        save: @escaping @Sendable (MemoryNote) -> Void = { _ = CorpusStore.save($0, includingTranscript: false) },
        appendTranscript: @escaping @Sendable ([TranscriptLine], MemoryNote) -> [UUID] = {
            CorpusStore.appendTranscript($0, to: $1)
        }
    ) {
        self.save = save
        self.appendTranscript = appendTranscript
    }

    func submit(_ record: MemoryNote) {
        let shouldSchedule = lock.withLock {
            pending[record.id] = record
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        queue.async { [self] in drain() }
    }

    func flush() {
        queue.sync {}
    }

    private func drain() {
        while let record = lock.withLock({ () -> MemoryNote? in
            guard let entry = pending.first else {
                drainScheduled = false
                return nil
            }
            pending.removeValue(forKey: entry.key)
            return entry.value
        }) {
            appendNewTurns(of: record)
            save(record)
        }
    }

    /// Writes the final turns this note has not written yet, in order, and only
    /// records them as written once the store confirms.
    private func appendNewTurns(of record: MemoryNote) {
        guard case .loaded(let lines) = record.transcript else { return }
        let known = lock.withLock { appended[record.id] ?? [] }
        let fresh = lines.filter { $0.isFinal && !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        // Only what the store confirms is remembered: a refused write leaves
        // the turn unrecorded so the next drain offers it again.
        let written = appendTranscript(fresh, record)
        lock.withLock { appended[record.id, default: []].formUnion(written) }
    }
}
