import Foundation

/// The OKF v0.2 corpus layout: where a note's `.md` and sibling folder live,
/// which names are reserved, and how a title becomes a unique slug within its
/// directory. See `specs/okf-corpus/design.md` §1.
///
/// Pure name/path calculation only — no filesystem access. `URL` values here
/// are constructed in-memory and never read or written.
enum OKFBundle {
    static let okfVersion = "0.2"
    static let rawDirectoryName = "raw"
    /// Where a note's document points at its captured transcript.
    static let transcriptRelativePath = "raw/transcript.md"
    static let attachmentsDirectoryName = "attachments"
    static let indexFileName = "index.md"
    static let logFileName = "log.md"
    static let agentsFileName = "AGENTS.md"

    /// Where a note lands when nothing else claims it. An ordinary note the
    /// user may rename or move — only the default is reserved, not the name.
    static let inboxSlug = "inbox"

    private static let maxSlugLength = 54
    private static let fallbackSlug = "nota"

    /// Whether `name` names an entry reserved by the bundle layout.
    ///
    /// Calling convention: pass the bare name (no extension) to test a
    /// directory-shaped reserved entry — currently only `raw`, the capture
    /// directory inside a note's own folder. It is never reserved at the
    /// bundle root, because the root is not itself a note's folder. Pass the
    /// name WITH its `.md` extension to test a file-shaped reserved entry —
    /// `index.md` and `log.md`, reserved at every level; `AGENTS.md`,
    /// reserved only at the bundle root. A bare name never matches a
    /// file-shaped entry and an extensioned name never matches the
    /// directory-shaped one; that asymmetry is deliberate, not an oversight.
    static func isReserved(_ name: String, atRoot: Bool) -> Bool {
        switch name {
        case indexFileName, logFileName:
            return true
        case agentsFileName:
            return atRoot
        case rawDirectoryName:
            return !atRoot
        default:
            return false
        }
    }

    /// Folds diacritics, replaces runs of non-alphanumerics with `-`,
    /// lowercases, and trims to `maxSlugLength` characters without leaving a
    /// hyphen at either border. A title that reduces to nothing becomes
    /// `"nota"`.
    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-").lowercased()
        let truncated = String(joined.prefix(maxSlugLength))
        let trimmed = trimmingHyphens(truncated)
        return trimmed.isEmpty ? fallbackSlug : trimmed
    }

    /// Disambiguates `title`'s slug against `taken`, the sibling slugs
    /// already used in the directory this slug will live in, and against the
    /// reserved-name set. Reserved-ness is evaluated as the non-root case
    /// (`raw` counts as taken; `AGENTS.md` does not, since it can only ever
    /// collide with a top-level note and is not exercised by this plan's
    /// fixtures) — a caller that specifically needs the root's relaxed rule
    /// calls `isReserved` directly. A candidate that is either reserved or
    /// already taken advances to the next numbered suffix: `-2`, `-3`, ….
    /// Reserved-ness and takenness share this single counter, so a reserved
    /// base whose first numbered candidate is itself taken skips ahead again.
    static func uniqueSlug(_ title: String, taken: Set<String>) -> String {
        let base = slug(title)
        var candidate = base
        var suffix = 2
        while isReservedCandidate(candidate) || taken.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Names an untitled session `yyyy-MM-dd-HHmm` in local time, so the name
    /// makes sense to someone browsing the Finder. `timeZone` defaults to
    /// `.current`; tests inject a fixed zone to stay deterministic.
    static func untitledSlug(startedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: startedAt)
    }

    static func noteURL(slug: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(slug).md")
    }

    static func noteFolder(slug: String, in directory: URL) -> URL {
        directory.appendingPathComponent(slug, isDirectory: true)
    }

    static func rawDirectory(slug: String, in directory: URL) -> URL {
        noteFolder(slug: slug, in: directory).appendingPathComponent(rawDirectoryName, isDirectory: true)
    }

    static func attachmentsDirectory(slug: String, in directory: URL) -> URL {
        rawDirectory(slug: slug, in: directory)
            .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
    }

    private static func isReservedCandidate(_ candidate: String) -> Bool {
        isReserved(candidate, atRoot: false) || isReserved("\(candidate).md", atRoot: false)
    }

    private static func trimmingHyphens(_ value: String) -> String {
        var scalars = Substring(value)
        while scalars.first == "-" { scalars = scalars.dropFirst() }
        while scalars.last == "-" { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
