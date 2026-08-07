import Foundation

struct MemoryChunk: Sendable, Hashable {
    enum Kind: String, Sendable { case content, transcript, topic, decision, action, question, note, artifact }
    let id: String; let sessionID: UUID; let projectID: UUID?; let kind: Kind
    let startedAt: Date; let timestamp: TimeInterval?; let text: String
}

enum MemoryChunkBuilder {
    /// Content signature over exactly the fields `chunks` indexes.
    ///
    /// The index is asked to rebuild on every library query, so this runs on the
    /// MainActor once per keystroke. Building the chunks just to hash them made
    /// that cost proportional to the whole archive — allocating a struct and a
    /// joined string per chunk — which stalled the live session. Hashing the same
    /// source fields keeps every in-memory edit detectable at a fraction of it.
    static func contentSignature(_ record: SessionRecord) -> Int {
        var hasher = Hasher()
        hasher.combine(record.id)
        hasher.combine(record.projectID)
        hasher.combine(record.title)
        hasher.combine(record.labels)
        hasher.combine(record.markdownBody)
        for line in record.transcript where line.isFinal {
            hasher.combine(line.speaker)
            hasher.combine(line.text)
            hasher.combine(line.translation)
        }
        for topic in record.minutes.topics {
            hasher.combine(topic.title)
            hasher.combine(topic.summary)
        }
        for decision in record.review.decisions { hasher.combine(decision.text) }
        for question in record.review.openQuestions { hasher.combine(question.text) }
        for takeaway in record.takeaways { hasher.combine(takeaway.text) }
        for note in record.notes { hasher.combine(note.text) }
        for artifact in record.artifacts {
            hasher.combine(artifact.title)
            hasher.combine(artifact.body)
        }
        return hasher.finalize()
    }

    static func chunks(_ record: SessionRecord) -> [MemoryChunk] {
        var result: [MemoryChunk] = []
        let finals = record.transcript.filter(\.isFinal)
        for start in stride(from: 0, to: finals.count, by: 5) {
            let lines = Array(finals[start..<min(finals.count, start + 7)])
            guard let first = lines.first else { continue }
            let body = lines.map {
                "\(record.participantName(for: $0.speaker)): \($0.text)\($0.translation.map { " | \($0)" } ?? "")"
            }.joined(separator: "\n")
            result.append(.init(id: "transcript:\(record.id):\(start)", sessionID: record.id,
                projectID: record.projectID, kind: .transcript, startedAt: record.startedAt,
                timestamp: first.ts.timeIntervalSince(record.audioTimelineStart), text: body))
        }
        func append(_ id: String, _ kind: MemoryChunk.Kind, _ text: String, _ timestamp: TimeInterval? = nil) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(.init(id: id, sessionID: record.id, projectID: record.projectID,
                kind: kind, startedAt: record.startedAt, timestamp: timestamp, text: text))
        }
        append(
            "content:\(record.id)",
            .content,
            ([record.title, record.labels.joined(separator: " "), record.markdownBody])
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        )
        record.minutes.topics.forEach { append("topic:\($0.id)", .topic, "\($0.title): \($0.summary)") }
        record.review.decisions.forEach { append("decision:\($0.id)", .decision, $0.text, $0.evidence.first?.timestamp) }
        record.takeaways.forEach { append("action:\($0.id)", .action, $0.text, $0.evidence.first?.timestamp) }
        record.review.openQuestions.forEach { append("question:\($0.id)", .question, $0.text, $0.evidence.first?.timestamp) }
        record.notes.forEach { append("note:\($0.id)", .note, $0.text, $0.timeOffset) }
        record.artifacts.forEach { append("artifact:\($0.id)", .artifact, "\($0.title): \($0.body)") }
        return result
    }
}
