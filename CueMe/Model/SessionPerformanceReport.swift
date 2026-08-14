import Foundation

enum CoachFeedback: String, Codable, Sendable, CaseIterable {
    case helpful, notHelpful
}

/// What the Integrity panel actually shows (AC3). Coach latency percentiles
/// depended on the full event log and left with `SessionPerformanceReport`
/// (ADR 0045) — only the two counters in `MemoryNote.integrity` survive.
struct SessionIntegrityReport: Sendable, Equatable {
    let recordingExpected: Bool
    let audioCoveragePercent: Int
    let transcriptTurns: Int
    let recoveries: Int
    let errors: Int

    init(record: MemoryNote) {
        recordingExpected = record.hasAudio
        if record.hasAudio, record.duration > 0 {
            audioCoveragePercent = min(100, max(0, Int((record.audioDuration / record.duration * 100).rounded())))
        } else {
            audioCoveragePercent = 0
        }
        transcriptTurns = record.transcript.filter(\.isFinal).count
        recoveries = record.integrity.recoveries
        errors = record.integrity.errors
    }

    var isHealthy: Bool { errors == 0 && (!recordingExpected || audioCoveragePercent >= 95) }
}
