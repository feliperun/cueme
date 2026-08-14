import Foundation

/// Flattens a note into the plain-text memory block handed to the model.
/// Kept apart from `SessionPostProcessor` so prompt orchestration does not have
/// to know the shape of every field on `MemoryNote`.
enum SessionMemoryDigest {
    static func text(for record: MemoryNote) -> String {
        var parts = [
            "Título: \(record.title)",
            "Objetivo: \(record.goal)",
            "Data: \(record.startedAt.formatted(date: .long, time: .shortened))"
        ]
        if !record.minutes.isEmpty {
            let topics = record.minutes.topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
            parts.append("Ata atual:\n\(record.minutes.overview)\n\(topics)")
        }
        if !record.notes.isEmpty {
            let notes = record.notes.map {
                "Nota \(SessionArchive.clock($0.timeOffset)): \($0.text)"
            }.joined(separator: "\n")
            parts.append("Anotações:\n\(notes)")
        }
        let transcript = record.transcript.filter(\.isFinal).map { line in
            let speaker = record.participantName(for: line.speaker).uppercased()
            let translation = line.translation.map { " | Tradução: \($0)" } ?? ""
            return "[\(speaker)] \(line.text)\(translation)"
        }.joined(separator: "\n")
        parts.append("Transcrição:\n\(transcript.isEmpty ? "(vazia)" : transcript)")
        return String(parts.joined(separator: "\n\n").prefix(60_000))
    }
}
