import XCTest
@testable import CueMe

final class FailoverCoachSessionTests: XCTestCase {
    func testSlowPrimaryFallsBackToSecondary() async throws {
        let primary = StubCoachSession(output: "primary", delay: .milliseconds(150))
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .milliseconds(10)
        )
        let result = try await session.complete("hello")
        XCTAssertEqual(result, "secondary")
        await session.shutdown()
    }

    func testFastPrimaryWins() async throws {
        let primary = StubCoachSession(output: "primary")
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .milliseconds(100)
        )
        let result = try await session.complete("hello")
        XCTAssertEqual(result, "primary")
        await session.shutdown()
    }

    func testPrimaryThatEmitsThenStallsFallsBackWithoutMixingOutputs() async throws {
        let primary = StubCoachSession(
            chunks: [("partial", .zero), ("never", .seconds(5))]
        )
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .milliseconds(20)
        )

        let result = try await session.complete("hello")

        XCTAssertEqual(result, "secondary")
        await session.shutdown()
    }

    /// The coach card is rendered from partial deltas, so a committed primary has
    /// to reach the consumer while it is still generating — never only at the end.
    func testCommittedPrimaryStreamsBeforeItFinishes() async throws {
        let primary = StubCoachSession(
            chunks: [("GUIA: ", .zero), ("plano", .zero), (" completo", .milliseconds(1_500))]
        )
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .seconds(10)
        )

        let clock = ContinuousClock()
        let start = clock.now
        var received: [String] = []
        var firstDeltaAfter: Duration?
        for try await delta in await session.send("hello") {
            if firstDeltaAfter == nil { firstDeltaAfter = start.duration(to: clock.now) }
            received.append(delta)
        }

        XCTAssertEqual(received, ["GUIA: ", "plano", " completo"])
        XCTAssertLessThan(firstDeltaAfter ?? .seconds(60), .milliseconds(700))
        await session.shutdown()
    }

    func testSingleDeltaPrimaryStillDelivers() async throws {
        let primary = StubCoachSession(output: "only")
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .seconds(5)
        )

        let result = try await session.complete("hello")

        XCTAssertEqual(result, "only")
        await session.shutdown()
    }
}

private actor StubCoachSession: CoachSession {
    let chunks: [(String, Duration)]

    init(output: String, delay: Duration = .zero) {
        self.chunks = [(output, delay)]
    }

    init(chunks: [(String, Duration)]) {
        self.chunks = chunks
    }

    func send(_ user: String) -> AsyncThrowingStream<String, Error> {
        let chunks = chunks
        return AsyncThrowingStream { continuation in
            let task = Task {
                for (output, delay) in chunks {
                    do { try await Task.sleep(for: delay) }
                    catch { continuation.finish(); return }
                    continuation.yield(output)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(_ user: String) async throws -> String { chunks.map(\.0).joined() }
    func prewarm() async throws {}
    func shutdown() async {}
}
