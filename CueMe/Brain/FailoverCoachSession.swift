import Foundation

/// Races the preferred provider against a delayed backup. The backup takes over
/// when the primary stalls for longer than the latency budget, or fails, before
/// the primary has committed to streaming. Once committed, the primary streams
/// straight through so the card stays incremental.
final class FailoverCoachSession: CoachSession, @unchecked Sendable {
    /// Deltas the primary must produce before its output starts streaming through.
    private static let commitThreshold = 2

    private let primary: any CoachSession
    private let secondary: any CoachSession
    private let delay: Duration
    private let onFailover: @Sendable () -> Void

    init(
        primary: any CoachSession,
        secondary: any CoachSession,
        delay: Duration = .seconds(4),
        onFailover: @escaping @Sendable () -> Void = {}
    ) {
        self.primary = primary
        self.secondary = secondary
        self.delay = delay
        self.onFailover = onFailover
    }

    func send(_ user: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let state = RelayState()
            let orchestration = Task {
                await self.runRace(user: user, state: state, continuation: continuation)
            }
            continuation.onTermination = { _ in orchestration.cancel() }
        }
    }

    private func runRace(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.relayPrimary(user: user, state: state, continuation: continuation)
            }
            group.addTask {
                await self.startDelayedBackup(user: user, state: state, continuation: continuation)
            }
            await group.waitForAll()
        }
    }

    private func relayPrimary(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let stream = await primary.send(user)
            // Deltas are held only until the primary proves it is really
            // streaming. Committing on the second delta keeps the card
            // incremental while a provider that emits one token and then hangs
            // still loses the race without any of its output being shown.
            var buffered: [String] = []
            var committed = false
            for try await delta in stream {
                guard !Task.isCancelled else { return }
                guard !state.isWinner(.secondary) else { return }
                state.notePrimaryActivity()
                if committed {
                    continuation.yield(delta)
                    continue
                }
                buffered.append(delta)
                guard buffered.count >= Self.commitThreshold, state.claim(.primary) else { continue }
                committed = true
                for pending in buffered { continuation.yield(pending) }
                buffered.removeAll()
            }
            if committed {
                if state.finish(.primary) { continuation.finish() }
            } else if state.claim(.primary) {
                for delta in buffered { continuation.yield(delta) }
                if state.finish(.primary) { continuation.finish() }
            }
        } catch {
            await recoverPrimary(error: error, user: user, state: state, continuation: continuation)
        }
    }

    private func recoverPrimary(
        error: Error,
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        if state.claim(.secondary) {
            onFailover()
            await Self.relaySecondary(secondary, user: user, state: state, continuation: continuation)
        } else if state.finish(.primary) {
            continuation.finish(throwing: error)
        }
    }

    private func startDelayedBackup(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        let components = delay.components
        let stallSeconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        while !Task.isCancelled {
            do { try await Task.sleep(for: delay) }
            catch { return }
            if state.claimSecondaryIfStalled(after: stallSeconds) {
                onFailover()
                await Self.relaySecondary(secondary, user: user, state: state, continuation: continuation)
                return
            }
            if state.hasWinner { return }
        }
    }

    private static func relaySecondary(
        _ secondary: any CoachSession,
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let stream = await secondary.send(user)
            for try await delta in stream {
                if Task.isCancelled || !state.isWinner(.secondary) { return }
                continuation.yield(delta)
            }
            if state.finish(.secondary) { continuation.finish() }
        } catch {
            if state.finish(.secondary) { continuation.finish(throwing: error) }
        }
    }

    func complete(_ user: String) async throws -> String {
        var result = ""
        let stream = await send(user)
        for try await delta in stream { result += delta }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prewarm() async throws {
        do { try await primary.prewarm() }
        catch {
            onFailover()
            try await secondary.prewarm()
        }
    }

    func shutdown() async {
        await primary.shutdown()
        await secondary.shutdown()
    }
}

private final class RelayState: @unchecked Sendable {
    enum Winner { case primary, secondary }
    private let lock = NSLock()
    private var winner: Winner?
    private var completed = false
    private var lastPrimaryActivity = Date()

    var hasWinner: Bool { lock.withLock { winner != nil || completed } }

    func notePrimaryActivity() {
        lock.withLock { lastPrimaryActivity = Date() }
    }

    func claimSecondaryIfStalled(after interval: TimeInterval) -> Bool {
        lock.withLock {
            guard winner == nil, !completed,
                  Date().timeIntervalSince(lastPrimaryActivity) >= interval else { return false }
            winner = .secondary
            return true
        }
    }

    func claim(_ candidate: Winner) -> Bool {
        lock.withLock {
            guard winner == nil, !completed else { return false }
            winner = candidate
            return true
        }
    }

    func isWinner(_ candidate: Winner) -> Bool {
        lock.withLock { winner == candidate && !completed }
    }

    func finish(_ candidate: Winner) -> Bool {
        lock.withLock {
            guard winner == candidate, !completed else { return false }
            completed = true
            return true
        }
    }
}
