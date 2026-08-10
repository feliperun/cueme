import Foundation

/// `log.md` — one file at the bundle root, **append-only**. Existing entries are
/// immutable; a new one is inserted into its date group, and the group is
/// created at the top when the day is new.
///
/// The file is never regenerated. That is the OKF convention, and it is what
/// keeps the diff quiet when the corpus lives in git. See
/// `specs/okf-corpus/contracts/log.md`.
enum CorpusLogDocument {
    /// Only durable structural events belong here. Ordinary edits do not — the
    /// file would become a keystroke journal.
    enum Operation: String {
        case created = "Criação"
        case moved = "Movimentação"
        case renamed = "Renomeação"
        case deleted = "Exclusão"
        case migrated = "Migração"
        case inconsistency = "Inconsistência"
    }

    static let heading = "# Histórico do corpus"

    static func appending(
        _ sentence: String,
        operation: Operation,
        on date: Date,
        to existing: String?,
        timeZone: TimeZone = .current
    ) -> String {
        let day = dayLabel(date, timeZone: timeZone)
        let entry = "- **\(operation.rawValue)**: \(sentence)"
        guard let existing, existing.contains(heading) else {
            return "\(heading)\n\n## \(day)\n\n\(entry)\n"
        }

        var lines = existing.components(separatedBy: "\n")
        if let start = lines.firstIndex(of: "## \(day)") {
            // Same day: the entry goes at the end of its own group, so every
            // byte before it stays exactly where it was.
            let next = lines[lines.index(after: start)...].firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
            var insertion = next
            while insertion > start + 1, lines[insertion - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertion -= 1
            }
            lines.insert(entry, at: insertion)
            return lines.joined(separator: "\n")
        }

        // A day with no group yet: place it so groups stay newest-first.
        let group = ["## \(day)", "", entry, ""]
        let existingGroups = lines.enumerated().filter { $0.element.hasPrefix("## ") }
        let position = existingGroups.first { $0.element.dropFirst(3) < Substring(day) }?.offset
            ?? lines.count
        lines.insert(contentsOf: group, at: position)
        return lines.joined(separator: "\n")
    }

    static func dayLabel(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `[Title](path.md)` for use inside an entry sentence.
    static func link(_ title: String, path: String) -> String {
        "[\(title)](\(path.hasPrefix("/") ? String(path.dropFirst()) : path))"
    }
}
