import Foundation

struct NoteTimelineEntry: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case meeting, decision, action, question }
    let id: String
    let sessionID: UUID
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
}

/// Chronological view of what happened inside a note's subtree. There is no
/// project entity any more: "belongs to" is where a note sits in the tree, so
/// the timeline is built from a set of notes the caller already chose.
enum KnowledgeTimeline {
    static func entries(for records: [MemoryNote]) -> [NoteTimelineEntry] {
        records.flatMap { record in
            var entries = [NoteTimelineEntry(
                id: "meeting-\(record.id)", sessionID: record.id, date: record.startedAt,
                kind: .meeting, title: record.title, detail: record.minutes.overview
            )]
            entries += record.review.decisions.map {
                .init(id: "decision-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .decision, title: "Decisão", detail: $0.text)
            }
            entries += record.takeaways.map {
                .init(id: "action-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .action, title: $0.isDone ? "Ação concluída" : "Ação pendente", detail: $0.text)
            }
            entries += record.review.openQuestions.map {
                .init(id: "question-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .question, title: "Questão em aberto", detail: $0.text)
            }
            return entries
        }.sorted { $0.date > $1.date }
    }
}
