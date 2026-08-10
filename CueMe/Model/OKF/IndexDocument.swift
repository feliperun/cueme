import Foundation

/// `index.md` — the reserved file that makes a level of the corpus navigable
/// without CueMe. It lists direct children only, so an agent discovers the tree
/// progressively instead of loading it whole.
///
/// The bundle root is the only `index.md` that carries `okf_version`; a nested
/// one has no frontmatter at all. See `specs/okf-corpus/contracts/index.md`.
enum IndexDocument {
    struct Entry: Equatable {
        let title: String
        let filename: String
        let description: String?
    }

    static let rootHeading = "Notas"

    /// Direct children of `directory`, sorted by title, as index entries.
    static func entries(in notes: [MemoryNote], directory: String) -> [Entry] {
        notes
            .filter { ($0.relativeFolderPath ?? "") == directory }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { note in
                let description = note.goal.trimmingCharacters(in: .whitespacesAndNewlines)
                return Entry(
                    title: note.title,
                    filename: "\(note.archiveFolderName).md",
                    description: description.isEmpty ? nil : description
                )
            }
    }

    static func render(heading: String, entries: [Entry], isRoot: Bool) -> String {
        var out = ""
        if isRoot {
            out += "---\nokf_version: \"\(OKFBundle.okfVersion)\"\n---\n\n"
        }
        out += "# \(heading)\n\n"
        for entry in entries {
            out += "* [\(entry.title)](\(entry.filename))"
            if let description = entry.description { out += " - \(description)" }
            out += "\n"
        }
        return out
    }
}
