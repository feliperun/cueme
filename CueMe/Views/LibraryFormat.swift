import Foundation

/// Presentation-only formatting for the library list. Split out of
/// `LibraryColumns` so the column views are not also the formatting rules.
enum LibraryFormat {
    static func kindTag(_ r: MemoryNote) -> String {
        switch r.libraryPresentationKind {
        case .note: return "NOTE"
        case .journal: return "JOURNAL"
        case .meeting: return "MEETING"
        }
    }

    static func rightMeta(_ r: MemoryNote) -> String {
        var parts = [relative(r.startedAt)]
        if r.containsRecording, r.audioDuration > 0 { parts.append(duration(r.audioDuration)) }
        return parts.joined(separator: " · ")
    }

    static func preview(_ r: MemoryNote, snippet: String?) -> String? {
        if let snippet, !snippet.isEmpty { return snippet }
        let overview = r.minutes.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty { return overview }
        let body = r.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : String(body.prefix(120))
    }

    static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Import status toast
