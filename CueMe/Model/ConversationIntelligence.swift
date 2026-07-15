import Foundation

/// Runtime classification used to adapt coaching without another network call.
/// The configured mode is a strong prior; meeting/custom modes are refined from
/// the latest turns so the UI and prompt can react immediately.
enum ConversationStyle: String, Codable, Sendable, CaseIterable {
    case interview
    case oneOnOne
    case technical
    case sales
    case openMeeting

    var label: String {
        switch self {
        case .interview: return "Entrevista"
        case .oneOnOne: return "1:1"
        case .technical: return "Técnica"
        case .sales: return "Vendas"
        case .openMeeting: return "Reunião"
        }
    }

    var coachingInstruction: String {
        switch self {
        case .interview:
            return "Responda com profundidade e rapidez; use fatos, STAR e resultado mensurável."
        case .oneOnOne:
            return "Ajude a formular feedback, alinhar expectativa e transformar tensão em pedido claro."
        case .technical:
            return "Priorize trade-offs, riscos, critérios, observabilidade, rollback e próximos experimentos."
        case .sales:
            return "Explore dor, impacto, objeção, valor e próximo passo concreto."
        case .openMeeting:
            return "Intervenha pouco; sugira pergunta forte, decisão ausente, dono, prazo ou risco."
        }
    }

    static func fallback(for mode: Mode) -> Self {
        switch mode {
        case .interview: return .interview
        case .sales: return .sales
        case .difficult: return .oneOnOne
        case .meeting, .recording, .custom: return .openMeeting
        }
    }
}

enum ConversationStyleDetector {
    private static let signals: [ConversationStyle: [String]] = [
        .interview: [
            "entrevista", "vaga", "candidato", "experiência profissional", "tell me about",
            "fale sobre você", "por que você", "strength", "weakness"
        ],
        .oneOnOne: [
            "feedback", "carreira", "crescimento", "desenvolvimento", "expectativa", "promoção",
            "performance", "desempenho", "como posso apoiar", "responsabilidade no time"
        ],
        .technical: [
            "arquitetura", "latência", "rollback", "observabilidade", "trade-off", "tradeoff",
            "api", "banco de dados", "deploy", "migração", "escala", "incidente", "infraestrutura"
        ],
        .sales: [
            "proposta", "preço", "orçamento", "contrato", "cliente", "prospect", "roi",
            "objeção", "fechamento", "comprar", "demo"
        ],
        .openMeeting: [
            "pauta", "status", "alinhamento", "próximo passo", "ficou combinado", "ata"
        ]
    ]

    static func detect(turns: [Turn], fallback mode: Mode) -> ConversationStyle {
        if mode == .interview { return .interview }
        if mode == .sales { return .sales }
        if mode == .difficult { return .oneOnOne }

        let text = turns.suffix(24).map(\.text).joined(separator: " ").lowercased()
        guard !text.isEmpty else { return .fallback(for: mode) }
        let scored = signals.map { style, terms in
            (style, terms.reduce(0) { $0 + (text.contains($1) ? 1 : 0) })
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 2 else {
            return .fallback(for: mode)
        }
        return best.0
    }
}

enum CoachOpportunityKind: String, Sendable, Equatable {
    case question, decision, ownership, risk, feedback, none
}

struct CoachOpportunity: Sendable, Equatable {
    let kind: CoachOpportunityKind
    let confidence: Double

    var isHighConfidence: Bool { confidence >= 0.82 }

    static func evaluate(text: String, style: ConversationStyle) -> Self {
        let normalized = CoachTriggerPolicy.fingerprint(text)
        guard normalized.split(separator: " ").count >= 4 else { return .init(kind: .none, confidence: 0) }

        let ownership = ["responsável", "quem faz", "quem vai", "prazo", "deadline", "owner"]
            .filter(normalized.contains).count
        if ownership >= 2 { return .init(kind: .ownership, confidence: 0.96) }
        if question(text) { return .init(kind: .question, confidence: 0.94) }
        if ["ficou decidido", "decidimos", "decisão", "vamos seguir", "opção escolhida"]
            .contains(where: normalized.contains) {
            return .init(kind: .decision, confidence: 0.88)
        }
        if ["risco", "dependência", "bloqueio", "rollback", "falha", "mitigar"]
            .contains(where: normalized.contains) {
            return .init(kind: .risk, confidence: style == .technical ? 0.9 : 0.84)
        }
        if style == .oneOnOne,
           ["feedback", "expectativa", "desenvolvimento", "desempenho", "carreira"]
            .contains(where: normalized.contains) {
            return .init(kind: .feedback, confidence: 0.86)
        }
        return .init(kind: .none, confidence: 0.25)
    }

    private static func question(_ value: String) -> Bool {
        if value.contains("?") { return true }
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let starters = [
            "what", "why", "how", "when", "where", "which", "who", "could you", "can you",
            "tell me", "walk me", "describe", "would you", "do you", "have you", "o que",
            "por que", "como", "quando", "onde", "qual", "quem", "você pode", "você já",
            "me conta", "me fala", "descreva"
        ]
        return starters.contains(where: lower.hasPrefix)
    }
}
