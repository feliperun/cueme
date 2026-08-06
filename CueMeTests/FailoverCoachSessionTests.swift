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
