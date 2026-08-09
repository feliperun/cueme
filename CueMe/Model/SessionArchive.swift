import Foundation

enum SessionArchive {
    static func folderName(startedAt: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: startedAt))_\(id.uuidString.prefix(8))"
    }

    static func markdown(for record: MemoryNote) -> String {
        var lines = NoteDocument.frontmatter(for: record) + [
            "",
            "# \(record.title)",
            "",
            "- Data: \(record.startedAt.formatted(date: .long, time: .shortened))",
            "- Duração: \(clock(record.duration))",
            "- Modo: \(record.mode.label)",
            "- Origem: \(record.origin.label)",
            "- Idioma: \(record.conversationLang)",
            ""
        ]
        lines += NoteDocument.userBodyLines(for: record)
        lines.append("")
        appendSummary(record, to: &lines)
        appendTakeaways(record, to: &lines)
        appendReview(record, to: &lines)
        appendNotes(record, to: &lines)
        appendCoach(record, to: &lines)
        appendTranscript(record, to: &lines)
        appendArtifacts(record, to: &lines)
        appendHealth(record, to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private static func appendSummary(_ record: MemoryNote, to lines: inout [String]) {
        guard !record.minutes.isEmpty else { return }
        lines += ["## Ata", ""]
        if !record.minutes.overview.isEmpty {
            lines += [record.minutes.overview, ""]
        }
        if !record.minutes.topics.isEmpty {
            lines += ["### Assuntos", ""]
            for topic in record.minutes.topics {
                lines += ["#### \(topic.title)", "", topic.summary, ""]
            }
        }
        lines.append("")
    }

    private static func appendTakeaways(_ record: MemoryNote, to lines: inout [String]) {
        lines += ["## Pendências", ""]
        if record.takeaways.isEmpty {
            lines.append("_Nenhuma pendência registrada._")
        } else {
            for item in record.takeaways {
                lines.append("- [\(item.isDone ? "x" : " ")] \(item.text)")
                appendEvidence(item.evidence, to: &lines)
            }
        }
        lines.append("")
    }

    private static func appendReview(_ record: MemoryNote, to lines: inout [String]) {
        guard !record.review.isEmpty else { return }
        if !record.review.decisions.isEmpty {
            lines += ["## Decisões", ""]
            for item in record.review.decisions {
                lines.append("- \(item.text)")
                appendEvidence(item.evidence, to: &lines)
            }
            lines.append("")
        }
        if !record.review.openQuestions.isEmpty {
            lines += ["## Questões em aberto", ""]
            for item in record.review.openQuestions {
                lines.append("- \(item.text)")
                appendEvidence(item.evidence, to: &lines)
            }
            lines.append("")
        }
        if !record.review.followUp.isEmpty {
            lines += ["## Follow-up", "", record.review.followUp, ""]
        }
    }

    private static func appendEvidence(_ evidence: [MemoryEvidence], to lines: inout [String]) {
        for source in evidence.prefix(3) {
            lines.append("  - Evidência [\(clock(source.timestamp))]: \(source.quote)")
        }
    }

    private static func appendNotes(_ record: MemoryNote, to lines: inout [String]) {
        guard !record.notes.isEmpty else { return }
        lines += ["## Anotações", ""]
        lines += record.notes.sorted { $0.timeOffset < $1.timeOffset }
            .map { "- [\(clock($0.timeOffset))] \($0.text)" }
        lines.append("")
    }

    private static func appendCoach(_ record: MemoryNote, to lines: inout [String]) {
        let cards = record.coachCards.filter(\.hasContent)
        guard !cards.isEmpty else { return }
        lines += ["## Coach", ""]
        for card in cards {
            lines.append("### \(clock(card.ts.timeIntervalSince(record.startedAt)))")
            if !card.guidePT.isEmpty { lines.append(card.guidePT) }
            if let phrase = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative) {
                lines.append("")
                lines.append("> \(phrase)")
            }
            lines.append("")
        }
    }

    private static func appendTranscript(_ record: MemoryNote, to lines: inout [String]) {
        guard !record.transcript.isEmpty else { return }
        lines += ["## Transcrição", ""]
        for line in record.transcript where line.isFinal {
            let offset = line.ts.timeIntervalSince(record.audioTimelineStart)
            lines.append("**\(record.participantName(for: line.speaker)) · \(clock(offset))**")
            lines.append(line.text)
            if line.wasEdited, let original = line.originalText {
                lines.append("")
                lines.append("_Corrigido. Original: \(original)_")
            }
            if let translation = line.translation, !translation.isEmpty {
                lines.append("")
                lines.append("_\(translation)_")
            }
            lines.append("")
        }
    }

    private static func appendArtifacts(_ record: MemoryNote, to lines: inout [String]) {
        guard !record.artifacts.isEmpty else { return }
        lines += ["## Conteúdo gerado", ""]
        for artifact in record.artifacts {
            lines += ["### \(artifact.title)", "", artifact.body, ""]
        }
    }

    private static func appendHealth(_ record: MemoryNote, to lines: inout [String]) {
        let report = SessionIntegrityReport(record: record)
        let audioCoverage = report.recordingExpected ? "\(report.audioCoveragePercent)%" : "desativada"
        lines += [
            "## Integridade da sessão", "",
            "- Cobertura de áudio: \(audioCoverage)",
            "- Falas transcritas: \(report.transcriptTurns)",
            "- Recuperações automáticas: \(report.recoveries)",
            "- Erros registrados: \(report.errors)", ""
        ]
    }
}
