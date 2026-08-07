import Foundation

/// Runs `operation` with a hard deadline and returns whether it finished in time.
///
/// Teardown paths await provider and framework calls that are outside our
/// control (`SpeechAnalyzer` results, WebSocket drains). A single one of them
/// hanging used to freeze the whole session stop, so every such await gets a
/// deadline: the caller always resumes, and the stuck work is cancelled and left
/// behind instead of blocking the UI.
@discardableResult
func withDeadline(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> Void
) async -> Bool {
    let arbiter = DeadlineArbiter()
    return await withCheckedContinuation { continuation in
        let work = Task.detached(priority: .userInitiated) {
            await operation()
            if arbiter.claim() { continuation.resume(returning: true) }
        }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: timeout)
            guard arbiter.claim() else { return }
            work.cancel()
            continuation.resume(returning: false)
        }
    }
}

/// Guarantees the continuation is resumed exactly once.
private final class DeadlineArbiter: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.withLock {
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }
}
