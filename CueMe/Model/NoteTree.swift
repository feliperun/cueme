import Foundation

/// Reads the filesystem entries `CorpusStore` needs at one directory level,
/// abstracted so a test can wrap the real filesystem and count calls instead
/// of faking file content. See `specs/okf-corpus/design.md` §8.
protocol NoteTreeFileReading {
    /// Base names (without `.md`) of the note files directly inside `url`.
    func noteFileBaseNames(at url: URL) -> Set<String>
    /// Names of the subdirectories directly inside `url`.
    func subdirectoryNames(at url: URL) -> Set<String>
    /// Full UTF-8 contents of a note file, or `nil` if it cannot be read.
    func contents(of url: URL) -> String?
}

/// The real, disk-backed implementation of `NoteTreeFileReading`.
struct DiskNoteTreeReading: NoteTreeFileReading {
    func noteFileBaseNames(at url: URL) -> Set<String> {
        Set(entries(at: url).compactMap { entry -> String? in
            guard entry.lastPathComponent.hasSuffix(".md"), !isDirectory(entry) else { return nil }
            return String(entry.lastPathComponent.dropLast(3))
        })
    }

    func subdirectoryNames(at url: URL) -> Set<String> {
        Set(entries(at: url).compactMap { isDirectory($0) ? $0.lastPathComponent : nil })
    }

    func contents(of url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func entries(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}

/// Recursively discovers the note tree under a corpus root: parent/child
/// hierarchy expressed purely by filesystem nesting (design.md §1 — "it lives
/// in the path and nowhere else"), skipping reserved names and never
/// descending into a note's `raw/` capture directory.
///
/// A directory without a sibling `.md` file is an orphan, not a data loss: its
/// children are discovered exactly as if the parent existed (design.md §8's
/// two-object invariant), and the orphan's path is reported so the caller can
/// log the inconsistency instead of silently swallowing it.
enum NoteTree {
    struct DiscoveryResult {
        var notes: [MemoryNote]
        var orphanFolders: [String]
    }

    static func discover(at root: URL, reading: NoteTreeFileReading) -> DiscoveryResult {
        var notes: [MemoryNote] = []
        var orphans: [String] = []
        walk(directory: root, relativePrefix: "", atRoot: true, reading: reading, notes: &notes, orphans: &orphans)
        return DiscoveryResult(notes: notes, orphanFolders: orphans)
    }

    /// The transcript's declared turn count from a note's own frontmatter
    /// (`x_cueme_transcript.turns`), read without loading `raw/transcript.md`
    /// itself — that is what keeps `.notLoaded(turns:)` honest (design.md §7).
    static func declaredTranscriptTurnCount(in markdown: String) -> Int {
        guard let parsed = OKFFrontmatter.decode(markdown, knownKeys: ["x_cueme_transcript"]),
              case let .mapping(pairs)? = parsed.fields["x_cueme_transcript"],
              case let .int(turns)? = pairs.first(where: { $0.0 == "turns" })?.1
        else { return 0 }
        return turns
    }

    private static func walk(
        directory: URL,
        relativePrefix: String,
        atRoot: Bool,
        reading: NoteTreeFileReading,
        notes: inout [MemoryNote],
        orphans: inout [String]
    ) {
        let noteBaseNames = reading.noteFileBaseNames(at: directory)
        let subdirectoryNames = reading.subdirectoryNames(at: directory)

        for base in noteBaseNames.sorted() {
            guard !OKFBundle.isReserved("\(base).md", atRoot: atRoot) else { continue }
            let relativePath = relativePrefix.isEmpty ? base : "\(relativePrefix)/\(base)"
            let mdURL = directory.appendingPathComponent("\(base).md")
            guard let markdown = reading.contents(of: mdURL) else { continue }
            guard var note = NoteDocumentReader.parse(
                markdown, slug: base, turns: declaredTranscriptTurnCount(in: markdown)
            ) else { continue }
            note.relativeFolderPath = relativePrefix
            note.archiveFolderName = base
            notes.append(note)

            if subdirectoryNames.contains(base) {
                walk(
                    directory: directory.appendingPathComponent(base, isDirectory: true),
                    relativePrefix: relativePath, atRoot: false,
                    reading: reading, notes: &notes, orphans: &orphans
                )
            }
        }

        for base in subdirectoryNames.sorted() where !noteBaseNames.contains(base) {
            guard !OKFBundle.isReserved(base, atRoot: atRoot) else { continue }
            let relativePath = relativePrefix.isEmpty ? base : "\(relativePrefix)/\(base)"
            orphans.append(relativePath)
            walk(
                directory: directory.appendingPathComponent(base, isDirectory: true),
                relativePrefix: relativePath, atRoot: false,
                reading: reading, notes: &notes, orphans: &orphans
            )
        }
    }
}
