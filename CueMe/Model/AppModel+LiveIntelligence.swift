import Foundation

@MainActor
extension AppModel {
    func updateConversationStyle() {
        let turns = transcript.filter(\.isFinal).suffix(24).map {
            Turn(id: $0.sourceTurnID ?? $0.id, speaker: $0.speaker, text: $0.text, ts: $0.ts)
        }
        let detected = ConversationStyleDetector.detect(turns: turns, fallback: brief.mode)
        guard detected != conversationStyle else { return }
        conversationStyle = detected
        recordDiagnostic(kind: .coach, name: "conversation_style", detail: detected.rawValue)
    }

    var liveHealthItems: [LiveHealthItem] {
        LiveHealthMonitor.snapshot(
            mic: micCaptureState,
            system: systemCaptureState,
            recordingEnabled: recordAudio,
            runtime: runtimeHealth,
            sttSource: sttSource,
            sttTurns: diagnostics.count("stt_final"),
            coachEnabled: !brief.mode.isPassive,
            coachReady: coachBackendReady,
            coachError: coachBackendError,
            summaryHasContent: !minutes.isEmpty,
            summaryError: summaryBackendError
        )
    }
}

