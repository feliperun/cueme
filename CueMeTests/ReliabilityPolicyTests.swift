import XCTest
@testable import CueMe

final class ReliabilityPolicyTests: XCTestCase {
    func testWatchdogRestartsOnlyStalledChannel() {
        let now = Date()
        var watchdog = RuntimeWatchdog(startedAt: now.addingTimeInterval(-10))
        watchdog.observeChunk(.self, at: now.addingTimeInterval(-10))
        watchdog.observeChunk(.other, at: now)
        XCTAssertEqual(
            watchdog.evaluate(now: now, micState: .active, systemState: .active, recordingFrames: nil),
            [.restartMicrophone]
        )
    }

    func testWatchdogRestartsSTTAfterRecentVoiceWithoutTranscript() {
        let now = Date()
        var watchdog = RuntimeWatchdog(startedAt: now.addingTimeInterval(-20))
        watchdog.observeLevel(.other, level: 0.5, at: now.addingTimeInterval(-7))
        watchdog.observeTranscript(.other, at: now.addingTimeInterval(-20))
        XCTAssertTrue(
            watchdog.evaluate(now: now, micState: .waiting, systemState: .waiting, recordingFrames: nil)
                .contains(.restartSTT(.other))
        )
    }

    func testAdaptiveTriggerRejectsUncertainStatement() {
        XCTAssertFalse(AdaptiveCoachTrigger.shouldTrigger(
            text: "I led the migration with my team",
            speakerCertain: false,
            stablePartial: true
        ))
        XCTAssertTrue(AdaptiveCoachTrigger.shouldTrigger(
            text: "How did you lead the migration with your team?",
            speakerCertain: true,
            stablePartial: true
        ))
    }

    /// AC3 — the Integrity panel shows exactly four aggregates: audio coverage,
    /// transcribed turns, recoveries and errors, all read from the persisted note.
    func testIntegrityReportShowsFourAggregates() {
        var record = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_100),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [
                TranscriptLine(speaker: .other, text: "Um", isFinal: true),
                TranscriptLine(speaker: .other, text: "Dois", isFinal: true),
                TranscriptLine(speaker: .other, text: "rascunho", isFinal: false)
            ],
            coachCards: [],
            summaryBullets: [],
            hasAudio: true,
            audioDuration: 90
        )
        record.integrity = NoteIntegrity(recoveries: 3, errors: 2)

        let report = SessionIntegrityReport(record: record)

        XCTAssertEqual(report.audioCoveragePercent, 90)
        XCTAssertEqual(report.transcriptTurns, 2)
        XCTAssertEqual(report.recoveries, 3)
        XCTAssertEqual(report.errors, 2)
    }

    /// AC4 — a recovery or error event bumps the matching counter in `integrity`,
    /// and nothing else does.
    func testRecoveryAndErrorEventsIncrementIntegrity() {
        let log = DiagnosticsLog(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ReliabilityPolicyTests-\(UUID().uuidString)", isDirectory: true),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        log.record(.init(kind: .transcription, name: "stt_final"))
        log.record(.init(kind: .recovery, name: "stt_restarted"))
        log.record(.init(kind: .recovery, name: "mic_watchdog_restart"))
        log.record(.init(kind: .error, name: "stt_send_failed"))

        XCTAssertEqual(log.integrity.recoveries, 2)
        XCTAssertEqual(log.integrity.errors, 1)
    }

    func testLiveHealthSnapshotKeepsEverySubsystemVisible() {
        let items = LiveHealthMonitor.snapshot(
            mic: .active,
            system: .recovering,
            recordingEnabled: true,
            runtime: .init(level: .degraded, reason: "Recuperando áudio da chamada"),
            sttSource: .deepgram,
            sttTurns: 12,
            coachEnabled: true,
            coachReady: true,
            coachError: nil,
            summaryHasContent: false,
            summaryError: nil
        )

        XCTAssertEqual(items.map(\.subsystem), LiveSubsystem.allCases)
        XCTAssertEqual(items.first { $0.subsystem == .microphone }?.state, .healthy)
        XCTAssertEqual(items.first { $0.subsystem == .callAudio }?.state, .recovering)
        XCTAssertEqual(items.first { $0.subsystem == .transcription }?.state, .healthy)
        XCTAssertEqual(items.first { $0.subsystem == .coach }?.state, .healthy)
        XCTAssertEqual(items.first { $0.subsystem == .summary }?.state, .waiting)
    }

    func testIntegrityReportDistinguishesDisabledFromMissingRecording() {
        let start = Date(timeIntervalSince1970: 1_000)
        func record(hasAudio: Bool) -> MemoryNote {
            MemoryNote(
                startedAt: start,
                endedAt: start.addingTimeInterval(60),
                mode: .meeting,
                training: false,
                conversationLang: "pt-BR",
                nativeLang: "pt-BR",
                goal: "",
                transcript: [],
                coachCards: [],
                summaryBullets: [],
                hasAudio: hasAudio,
                audioDuration: 0
            )
        }

        XCTAssertTrue(SessionIntegrityReport(record: record(hasAudio: false)).isHealthy)
        XCTAssertFalse(SessionIntegrityReport(record: record(hasAudio: true)).isHealthy)
    }

    func testPermissionDiagnosisDetectsChangedIdentity() {
        XCTAssertEqual(
            PermissionDiagnosis.evaluate(
                preflightGranted: true,
                captureSucceeded: false,
                currentIdentity: "TEAM:new",
                lastSuccessfulIdentity: "TEAM:old"
            ),
            .identityChanged
        )
    }

    func testVirtualSixtyMinuteSoakStaysHealthyAndDetectsInjectedFailures() {
        let start = Date(timeIntervalSince1970: 1_000)
        var watchdog = RuntimeWatchdog(startedAt: start)
        var frames: Int64 = 0

        for tick in 0..<(60 * 30) { // 60 minutes, one tick every two seconds
            let now = start.addingTimeInterval(Double(tick * 2))
            frames += 32_000
            watchdog.observeChunk(.self, at: now)
            watchdog.observeChunk(.other, at: now)
            if tick.isMultiple(of: 5) {
                watchdog.observeLevel(.self, level: 0.3, at: now)
                watchdog.observeLevel(.other, level: 0.3, at: now)
                watchdog.observeTranscript(.self, at: now)
                watchdog.observeTranscript(.other, at: now)
            }
            XCTAssertTrue(
                watchdog.evaluate(
                    now: now,
                    micState: .active,
                    systemState: .active,
                    recordingFrames: frames
                ).isEmpty
            )
        }

        let stalledAt = start.addingTimeInterval(3_606)
        watchdog.observeChunk(.self, at: stalledAt)
        XCTAssertTrue(
            watchdog.evaluate(
                now: stalledAt,
                micState: .active,
                systemState: .active,
                recordingFrames: frames + 32_000
            ).contains(.restartSystemCapture)
        )

        watchdog.observeChunk(.other, at: stalledAt)
        var recorderAction = false
        for offset in stride(from: 2, through: 10, by: 2) {
            let now = stalledAt.addingTimeInterval(Double(offset))
            watchdog.observeChunk(.self, at: now)
            watchdog.observeChunk(.other, at: now)
            recorderAction = recorderAction || watchdog.evaluate(
                now: now,
                micState: .active,
                systemState: .active,
                recordingFrames: frames + 32_000
            ).contains(.recordingStalled)
        }
        XCTAssertTrue(recorderAction)
    }

}
