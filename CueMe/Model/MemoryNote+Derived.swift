import Foundation

/// Values derived from a note's stored fields, plus the mutations that keep
/// `modifiedAt` and `titleSource` honest. Kept apart from the stored shape so
/// `MemoryNote.swift` stays a declaration of what is durable.
extension MemoryNote {
    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    var audioTimelineStart: Date { recordingStartedAt ?? startedAt }

    /// Título: primeira pergunta do interlocutor, senão modo + treino.
    var title: String {
        if let displayTitle = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !displayTitle.isEmpty {
            return String(displayTitle.prefix(120))
        }
        if let q = transcript.first(where: { $0.speaker == .other && $0.isFinal })?.text, !q.isEmpty {
            return String(q.prefix(80))
        }
        return training ? "Treino · \(mode.label)" : mode.label
    }

    var storageRelativePath: String {
        guard let relativeFolderPath,
              !relativeFolderPath.hasPrefix("/"),
              !relativeFolderPath.split(separator: "/").contains("..") else {
            return archiveFolderName
        }
        return relativeFolderPath
    }

    var containsRecording: Bool {
        hasAudio || attachments.contains { $0.kind == .recording || $0.kind == .audio }
    }

    /// One line that stands in for the note wherever a preview is needed.
    /// Derived from the minutes rather than kept in a parallel field, so it can
    /// never drift out of sync with them.
    var shortSummary: String {
        let overview = minutes.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty { return overview }
        if let topic = minutes.topics.first { return "\(topic.title): \(topic.summary)" }
        return title
    }

    var turnCount: Int { transcript.filter { $0.isFinal }.count }
    var isForeign: Bool { SessionBrief.baseCode(conversationLang) != SessionBrief.baseCode(nativeLang) }

    func participantName(for speaker: Speaker) -> String {
        let fallback = speaker.label
        let value = participantNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    mutating func rename(to rawTitle: String) {
        let clean = Self.cleanTitle(rawTitle)
        guard !clean.isEmpty else { return }
        displayTitle = clean
        titleSource = .user
        modifiedAt = Date()
    }

    mutating func applyGeneratedTitle(_ rawTitle: String) {
        guard titleSource != .user else { return }
        let clean = Self.cleanTitle(rawTitle)
        guard !clean.isEmpty else { return }
        displayTitle = clean
        titleSource = .generated
        modifiedAt = Date()
    }

    mutating func setLabels(_ values: [String]) {
        labels = Self.normalizedLabels(values)
        modifiedAt = Date()
    }

    private static func cleanTitle(_ value: String) -> String {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean = clean.drop(while: { $0 == "#" || $0.isWhitespace })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        return String(clean.prefix(120))
    }

    /// Nome de arquivo sugerido pra exportação.
    var exportFilename: String {
        let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "CueMe-\(training ? "treino" : mode.rawValue)-\(stamp).json"
    }

    /// JSON legível (pretty) pra copiar/exportar.
    var prettyJSON: String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? e.encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
