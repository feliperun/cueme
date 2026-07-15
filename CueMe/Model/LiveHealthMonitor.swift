import Foundation

enum LiveSubsystem: String, CaseIterable, Sendable, Identifiable {
    case microphone, callAudio, recording, transcription, coach, summary
    var id: String { rawValue }

    var label: String {
        switch self {
        case .microphone: return "Microfone"
        case .callAudio: return "Interlocutor"
        case .recording: return "Gravação"
        case .transcription: return "Transcrição"
        case .coach: return "Coach"
        case .summary: return "Ata"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .callAudio: return "headphones"
        case .recording: return "record.circle"
        case .transcription: return "captions.bubble.fill"
        case .coach: return "sparkles"
        case .summary: return "list.bullet.rectangle"
        }
    }
}

enum LiveHealthState: String, Sendable, Equatable {
    case disabled, waiting, healthy, recovering, failed
}

struct LiveHealthItem: Sendable, Equatable, Identifiable {
    let subsystem: LiveSubsystem
    let state: LiveHealthState
    let detail: String
    var id: LiveSubsystem { subsystem }
}

enum LiveHealthMonitor {
    static func snapshot(
        mic: CaptureChannelState,
        system: CaptureChannelState,
        recordingEnabled: Bool,
        runtime: RuntimeHealth,
        sttSource: SttSource,
        sttTurns: Int,
        coachEnabled: Bool,
        coachReady: Bool,
        coachError: String?,
        summaryHasContent: Bool,
        summaryError: String?
    ) -> [LiveHealthItem] {
        [
            .init(subsystem: .microphone, state: state(for: mic), detail: captureDetail(mic)),
            .init(subsystem: .callAudio, state: state(for: system), detail: captureDetail(system)),
            .init(
                subsystem: .recording,
                state: recordingState(enabled: recordingEnabled, runtime: runtime),
                detail: recordingEnabled ? "Áudio sendo salvo" : "Gravação desativada"
            ),
            .init(
                subsystem: .transcription,
                state: transcriptionState(runtime: runtime, turns: sttTurns),
                detail: sttTurns > 0 ? "\(sttTurns) falas · \(sttSource.label)" : sttSource.label
            ),
            .init(
                subsystem: .coach,
                state: !coachEnabled ? .disabled : (coachError != nil ? .failed : (coachReady ? .healthy : .waiting)),
                detail: !coachEnabled ? "Desativado neste modo" : (coachError ?? (coachReady ? "Pronto" : "Conectando"))
            ),
            .init(
                subsystem: .summary,
                state: summaryError != nil ? .failed : (summaryHasContent ? .healthy : .waiting),
                detail: summaryError ?? (summaryHasContent ? "Ata atualizada" : "Aguardando contexto")
            )
        ]
    }

    private static func state(for channel: CaptureChannelState) -> LiveHealthState {
        switch channel {
        case .waiting: return .waiting
        case .active: return .healthy
        case .recovering: return .recovering
        case .silent, .unavailable: return .failed
        }
    }

    private static func captureDetail(_ channel: CaptureChannelState) -> String {
        switch channel {
        case .waiting: return "Aguardando sinal"
        case .active: return "Captando"
        case .silent: return "Sem sinal"
        case .recovering: return "Recuperando automaticamente"
        case .unavailable: return "Indisponível"
        }
    }

    private static func recordingState(enabled: Bool, runtime: RuntimeHealth) -> LiveHealthState {
        guard enabled else { return .disabled }
        if runtime.reason?.localizedCaseInsensitiveContains("gravação") == true { return .failed }
        return .healthy
    }

    private static func transcriptionState(runtime: RuntimeHealth, turns: Int) -> LiveHealthState {
        if runtime.reason?.localizedCaseInsensitiveContains("transcrição") == true {
            return runtime.level == .critical ? .failed : .recovering
        }
        return turns > 0 ? .healthy : .waiting
    }
}

