import Foundation

/// Detects an actionable, stable partial before the speech recognizer emits a
/// final. Repeated normalized text is considered stable; each utterance fires once.
struct SpeculativeTurnDetector: Sendable {
    private(set) var lastText = ""
    private(set) var repetitions = 0
    private(set) var lastTriggered = ""

    mutating func observe(_ text: String, looksActionable: (String) -> Bool) -> Bool {
        let normalized = Self.normalize(text)
        guard normalized.split(separator: " ").count >= 4 else { return false }
        if normalized == lastText {
            repetitions += 1
        } else {
            lastText = normalized
            repetitions = 1
        }
        guard repetitions >= 2, normalized != lastTriggered, looksActionable(text) else { return false }
        lastTriggered = normalized
        return true
    }

    mutating func finalize() { lastText = ""; repetitions = 0 }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct SummarySchedulePolicy: Sendable {
    private(set) var finalTurnCount = 0
    private(set) var summarizedTurnCount = 0
    private var startedAt: Date
    private var lastSummaryAt: Date?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func registerFinalTurn(at now: Date = Date()) -> Bool {
        finalTurnCount += 1
        let newTurns = finalTurnCount - summarizedTurnCount
        if lastSummaryAt == nil {
            return newTurns >= 8 && now.timeIntervalSince(startedAt) >= 45
        }
        return newTurns >= 12 && now.timeIntervalSince(lastSummaryAt!) >= 120
    }

    mutating func markSummarized(at now: Date = Date(), turnCount: Int? = nil) {
        summarizedTurnCount = min(turnCount ?? finalTurnCount, finalTurnCount)
        lastSummaryAt = now
    }
    var hasUnsummarizedTurns: Bool { finalTurnCount > summarizedTurnCount }
}

enum CoachTriggerPolicy {
    static func fingerprint(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func shouldTrigger(
        text: String,
        mode: Mode,
        style: ConversationStyle? = nil,
        speakerCertain: Bool,
        now: Date = Date(),
        lastTriggeredAt: Date?,
        lastFingerprint: String?
    ) -> Bool {
        guard !mode.isPassive, speakerCertain else { return false }
        let normalized = fingerprint(text)
        guard normalized.split(separator: " ").count >= 4,
              normalized != lastFingerprint else { return false }

        let resolvedStyle = style ?? .fallback(for: mode)
        let opportunity = CoachOpportunity.evaluate(text: text, style: resolvedStyle)
        let meetingFallback = mode == .meeting
            && (text.contains("?") || normalized.split(separator: " ").count >= 12)
        guard opportunity.isHighConfidence || meetingFallback else { return false }

        let cooldown = self.cooldown(text: text, style: resolvedStyle)
        if let lastTriggeredAt, now.timeIntervalSince(lastTriggeredAt) < cooldown { return false }
        return true
    }

    /// Single source of truth for the pacing between cues. The gate and the
    /// countdown shown in the UI must never disagree about how long the wait is.
    static func cooldown(text: String, style: ConversationStyle) -> TimeInterval {
        let opportunity = CoachOpportunity.evaluate(text: text, style: style)
        let isQuestion = opportunity.kind == .question || text.contains("?")
        switch style {
        case .interview: return isQuestion ? 5 : 30
        case .sales: return isQuestion ? 10 : 30
        case .oneOnOne: return 30
        case .technical: return isQuestion ? 12 : 30
        case .openMeeting: return isQuestion ? 20 : 45
        }
    }

    static func cooldownRemaining(
        text: String,
        mode: Mode,
        style: ConversationStyle,
        now: Date = Date(),
        lastTriggeredAt: Date?
    ) -> TimeInterval {
        guard let lastTriggeredAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastTriggeredAt)
        return max(0, cooldown(text: text, style: style) - elapsed)
    }
}

enum LatencyFallback {
    static func guide(for text: String, mode: Mode) -> String {
        let lower = text.lowercased()
        if lower.contains("why") || lower.contains("por que") {
            return "MOTIVO → EVIDÊNCIA → IMPACTO"
        }
        if lower.contains("how") || lower.contains("como") {
            return "PLANO → AÇÃO → RESULTADO"
        }
        switch mode {
        case .interview: return "CONTEXTO → AÇÃO → RESULTADO"
        case .sales: return "DOR → VALOR → PRÓXIMO PASSO"
        case .difficult: return "FATO → SENTIMENTO → PEDIDO"
        case .custom: return "PONTO → PROVA → CONCLUSÃO"
        case .meeting: return "FATO → DECISÃO → RESPONSÁVEL"
        case .recording: return "FATO → DECISÃO → RESPONSÁVEL"
        }
    }
}

enum PreflightCheck: String, CaseIterable, Sendable, Identifiable {
    case microphone, systemAudio, coach
    var id: String { rawValue }
    var label: String {
        switch self {
        case .microphone: return "MIC"
        case .systemAudio: return "CALL"
        case .coach: return "COACH"
        }
    }
}

enum PreflightStatus: Sendable, Equatable {
    case idle, checking, passed, failed
}
