import AVFoundation
import XCTest
@testable import CueMe

final class LiveAudioRouterTests: XCTestCase {
    func testRouterDrainsEveryCapturedChunkBeforeCompleting() async throws {
        let mic = CountingSttSession()
        let router = LiveAudioRouter(micStt: mic, systemStt: nil, recorder: nil)
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .unbounded)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64

        let routeTask = Task { await router.run(pair.stream) }
        for offset in 0..<1_000 {
            pair.continuation.yield(AudioChunk(
                source: .self,
                buffer: buffer,
                ts: Date(timeIntervalSince1970: TimeInterval(offset))
            ))
        }
        pair.continuation.finish()
        await routeTask.value

        let feedCount = await mic.feedCount()
        XCTAssertEqual(feedCount, 1_000)
        let health = await router.healthSnapshot()
        XCTAssertEqual(health.routedChunks, 1_000)
        XCTAssertEqual(health.lastChunkAt[.self], Date(timeIntervalSince1970: 999))
    }
}

private actor CountingSttSession: SttSession {
    nonisolated let events = AsyncStream<TranscriptEvent> { $0.finish() }
    private var count = 0

    func start() async throws {}
    func feed(_ buffer: AVAudioPCMBuffer) { count += 1 }
    func finish() async {}
    func feedCount() -> Int { count }
}
