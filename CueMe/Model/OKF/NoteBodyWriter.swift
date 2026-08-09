import Foundation

/// Renders the Markdown body of a note document: the H1, the user's own
/// writing, and each marker-delimited section. Split out of
/// `NoteDocumentWriter`, which owns the frontmatter and the entry point.
enum NoteBodyWriter {
    static func render(_ note: MemoryNote, evidence: [MemoryEvidence]) -> String {
        var lines = ["", "# \(note.title)", ""]
        let userBody = OKFSectionMarkers.escape(note.markdownBody).trimmingCharacters(in: .newlines)
        if !userBody.isEmpty {
            lines += userBody.components(separatedBy: "\n") + [""]
        }
        lines += renderMinutes(note)
        lines += renderTakeaways(note)
        lines += renderReviewItems(note.review.decisions, section: .decisions, heading: "Decisões")
        lines += renderReviewItems(note.review.openQuestions, section: .openQuestions, heading: "Questões em aberto")
        lines += renderFollowUp(note)
        lines += renderNotes(note)
        lines += renderCoach(note)
        lines += renderArtifacts(note)
        lines += renderSources(evidence)
        let residual = note.residualMarkdown.trimmingCharacters(in: .newlines)
        if !residual.isEmpty { lines += residual.components(separatedBy: "\n") + [""] }
        return lines.joined(separator: "\n")
    }

    private static func sectionHeader(_ section: OKFSection, _ heading: String) -> [String] {
        [OKFSectionMarkers.marker(section), "## \(heading)", ""]
    }

    private static func renderMinutes(_ note: MemoryNote) -> [String] {
        guard !note.minutes.isEmpty else { return [] }
        var lines = sectionHeader(.minutes, "Ata")
        let overview = OKFSectionMarkers.escape(note.minutes.overview).trimmingCharacters(in: .newlines)
        if !overview.isEmpty { lines += overview.components(separatedBy: "\n") + [""] }
        for topic in note.minutes.topics {
            lines.append("### \(topic.title)" + NoteItemAttributeCodec.encode([
                ("id", .string(topic.id.uuidString.lowercased())),
                ("at", .date(topic.updatedAt))
            ]))
            lines.append("")
            let summary = OKFSectionMarkers.escape(topic.summary).trimmingCharacters(in: .newlines)
            if !summary.isEmpty { lines += summary.components(separatedBy: "\n") + [""] }
        }
        return lines
    }

    private static func renderTakeaways(_ note: MemoryNote) -> [String] {
        guard !note.takeaways.isEmpty else { return [] }
        var lines = sectionHeader(.takeaways, "Pendências")
        for item in note.takeaways {
            var attributes: [(String, OKFValue)] = [
                ("id", .string(item.id.uuidString.lowercased())),
                ("at", .date(item.createdAt))
            ]
            if let confidence = item.confidence { attributes.append(("confidence", .double(confidence))) }
            if let assignee = item.assignee { attributes.append(("assignee", .string(assignee))) }
            if let dueAt = item.dueAt { attributes.append(("due", .date(dueAt))) }
            lines.append(
                "- [\(item.isDone ? "x" : " ")] "
                    + itemText(item.text, evidence: item.evidence)
                    + NoteItemAttributeCodec.encode(attributes)
            )
        }
        return lines + [""]
    }

    private static func renderReviewItems(
        _ items: [MeetingReviewItem],
        section: OKFSection,
        heading: String
    ) -> [String] {
        guard !items.isEmpty else { return [] }
        var lines = sectionHeader(section, heading)
        for item in items {
            var attributes: [(String, OKFValue)] = [("id", .string(item.id.uuidString.lowercased()))]
            if let confidence = item.confidence { attributes.append(("confidence", .double(confidence))) }
            if let supersedes = item.supersedesID {
                attributes.append(("supersedes", .string(supersedes.uuidString.lowercased())))
            }
            lines.append("- " + itemText(item.text, evidence: item.evidence) + NoteItemAttributeCodec.encode(attributes))
        }
        return lines + [""]
    }

    private static func renderFollowUp(_ note: MemoryNote) -> [String] {
        let value = OKFSectionMarkers.escape(note.review.followUp).trimmingCharacters(in: .newlines)
        guard !value.isEmpty else { return [] }
        return sectionHeader(.followUp, "Follow-up") + value.components(separatedBy: "\n") + [""]
    }

    private static func renderNotes(_ note: MemoryNote) -> [String] {
        guard !note.notes.isEmpty else { return [] }
        var lines = sectionHeader(.notes, "Anotações")
        for item in note.notes.sorted(by: { $0.timeOffset < $1.timeOffset }) {
            lines.append("- " + OKFSectionMarkers.escape(item.text) + NoteItemAttributeCodec.encode([
                ("id", .string(item.id.uuidString.lowercased())),
                ("t", .double(item.timeOffset)),
                ("at", .date(item.createdAt))
            ]))
        }
        return lines + [""]
    }

    private static func renderCoach(_ note: MemoryNote) -> [String] {
        let cards = note.coachCards.filter(\.hasContent)
        guard !cards.isEmpty else { return [] }
        var lines = sectionHeader(.coach, "Coach")
        for card in cards {
            var attributes: [(String, OKFValue)] = [
                ("id", .string(card.id.uuidString.lowercased())),
                ("ts", .date(card.ts)),
                ("kind", .string(card.kind.rawValue)),
                ("severity", .string(card.severity.rawValue))
            ]
            if !card.keytermsConversation.isEmpty {
                attributes.append(("keyterms", .array(card.keytermsConversation.map { .string($0) })))
            }
            let clock = SessionArchive.clock(card.ts.timeIntervalSince(note.audioTimelineStart))
            lines.append("### \(clock)" + NoteItemAttributeCodec.encode(attributes))
            lines.append("")
            let guide = OKFSectionMarkers.escape(card.guidePT).trimmingCharacters(in: .newlines)
            if !guide.isEmpty { lines += guide.components(separatedBy: "\n") + [""] }
            var spoken: [String] = []
            if let conversation = card.sayConversation, !conversation.isEmpty {
                spoken.append("<!--cueme:say-conv-->" + OKFSectionMarkers.escape(conversation))
            }
            if !card.sayNative.isEmpty {
                spoken.append("<!--cueme:say-native-->" + OKFSectionMarkers.escape(card.sayNative))
            }
            if !spoken.isEmpty { lines += spoken + [""] }
        }
        return lines
    }

    private static func renderArtifacts(_ note: MemoryNote) -> [String] {
        guard !note.artifacts.isEmpty else { return [] }
        var lines = [OKFSectionMarkers.marker(.artifacts), "## Conteúdo gerado", ""]
        for artifact in note.artifacts {
            lines.append("### \(artifact.title)" + NoteItemAttributeCodec.encode([
                ("id", .string(artifact.id.uuidString.lowercased())),
                ("kind", .string(artifact.kind.rawValue)),
                ("at", .date(artifact.createdAt))
            ]))
            lines.append("")
            let body = OKFSectionMarkers.escape(artifact.body).trimmingCharacters(in: .newlines)
            if !body.isEmpty { lines += body.components(separatedBy: "\n") + [""] }
        }
        return lines
    }

    private static func renderSources(_ evidence: [MemoryEvidence]) -> [String] {
        guard !evidence.isEmpty else { return [] }
        return [OKFSectionMarkers.marker(.sources)]
            + evidence.map { "[^\(NoteDocumentWriter.sourceID($0))]: \($0.quote)" }
            + [""]
    }

    private static func itemText(_ raw: String, evidence: [MemoryEvidence]) -> String {
        OKFSectionMarkers.escape(raw) + evidence.map { "[^\(NoteDocumentWriter.sourceID($0))]" }.joined()
    }
}
