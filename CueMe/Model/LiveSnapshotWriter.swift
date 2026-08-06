import Foundation

/// Serializes live archive snapshots away from the MainActor and coalesces bursts
/// to the newest record. `flush()` is used only at session shutdown so the final
/// authoritative save cannot be overwritten by an older queued snapshot.
final class LiveSnapshotWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CueMe.LiveSnapshotWriter", qos: .utility)
    private let lock = NSLock()
    private var pending: [UUID: SessionRecord] = [:]
    private var drainScheduled = false
    private let save: @Sendable (SessionRecord) -> Void

    init(save: @escaping @Sendable (SessionRecord) -> Void = { _ = SessionStore.save($0) }) {
        self.save = save
    }

    func submit(_ record: SessionRecord) {
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
        while let record = lock.withLock({ () -> SessionRecord? in
            guard let entry = pending.first else {
                drainScheduled = false
                return nil
            }
            pending.removeValue(forKey: entry.key)
            return entry.value
        }) {
            save(record)
        }
    }
}
