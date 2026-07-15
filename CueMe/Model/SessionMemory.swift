import Foundation

struct SessionNote: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var timeOffset: TimeInterval
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), timeOffset: TimeInterval, text: String, createdAt: Date = Date()) {
        self.id = id
        self.timeOffset = max(0, timeOffset)
        self.text = text
        self.createdAt = createdAt
    }
}

struct SessionTakeaway: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date

    init(id: UUID = UUID(), text: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

struct MeetingReviewItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct MeetingReview: Codable, Sendable, Hashable {
    var decisions: [MeetingReviewItem]
    var openQuestions: [MeetingReviewItem]
    var followUp: String

    init(
        decisions: [MeetingReviewItem] = [],
        openQuestions: [MeetingReviewItem] = [],
        followUp: String = ""
    ) {
        self.decisions = decisions
        self.openQuestions = openQuestions
        self.followUp = followUp
    }

    static let empty = MeetingReview()
    var isEmpty: Bool {
        decisions.isEmpty && openQuestions.isEmpty
            && followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SessionReviewExtraction: Sendable, Equatable {
    var minutes: MeetingMinutes
    var takeaways: [SessionTakeaway]
    var review: MeetingReview
}

enum FollowUpFormat: String, CaseIterable, Sendable, Identifiable {
    case email, slack, minutes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .email: return "E-mail"
        case .slack: return "Slack"
        case .minutes: return "Ata"
        }
    }

    var icon: String {
        switch self {
        case .email: return "envelope"
        case .slack: return "bubble.left.and.bubble.right"
        case .minutes: return "doc.text"
        }
    }

    var request: String {
        switch self {
        case .email:
            return "Escreva um e-mail de follow-up curto com decisões, ações e dúvidas abertas."
        case .slack:
            return "Escreva uma atualização curta para Slack com decisões, responsáveis e próximos passos."
        case .minutes:
            return "Gere uma ata formal em Markdown com resumo, assuntos, decisões, ações e questões abertas."
        }
    }
}

enum SessionArtifactKind: String, Codable, Sendable, Hashable {
    case review
    case summary
    case takeaways
    case answer
    case custom
}

struct SessionArtifact: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var kind: SessionArtifactKind
    var title: String
    var body: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: SessionArtifactKind,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}
