import Foundation

/// Lossless, off-main fan-out from capture to STT and durable recording.
/// The coordinator may replace either STT lane while this actor keeps draining
/// the same capture stream.
actor LiveAudioRouter {
    struct HealthSnapshot: Sendable, Equatable {
        let routedChunks: Int64
        let lastChunkAt: [Speaker: Date]
    }

    private var micStt: (any SttSession)?
    private var systemStt: (any SttSession)?
    private var recorder: MeetingRecorder?
    private var routedChunks: Int64 = 0
    private var lastChunkAt: [Speaker: Date] = [:]

    init(
        micStt: (any SttSession)?,
        systemStt: (any SttSession)?,
        recorder: MeetingRecorder?
    ) {
        self.micStt = micStt
        self.systemStt = systemStt
        self.recorder = recorder
    }

    func replaceSTT(_ session: any SttSession, for speaker: Speaker) {
        switch speaker {
        case .self: micStt = session
        case .other: systemStt = session
        }
    }

    func run(_ chunks: AsyncStream<AudioChunk>) async {
        for await chunk in chunks {
            guard !Task.isCancelled else { return }
            routedChunks += 1
            lastChunkAt[chunk.source] = chunk.ts
            let stt = chunk.source == .self ? micStt : systemStt
            let recorder = recorder
            await withTaskGroup(of: Void.self) { group in
                if let stt {
                    group.addTask { await stt.feed(chunk.buffer) }
                }
                if let recorder {
                    group.addTask { await recorder.ingest(chunk) }
                }
                await group.waitForAll()
            }
        }
    }

    func healthSnapshot() -> HealthSnapshot {
        .init(routedChunks: routedChunks, lastChunkAt: lastChunkAt)
    }
}
