import Foundation
import OSLog

/// Filesystem side of the OKF corpus. Discovers the note tree, loads notes
/// (and their transcripts, on demand), saves, and deletes — replacing
/// `SessionStore`, which now delegates here. See
/// `specs/okf-corpus/design.md` §1 (layout), §7 (transcript on demand) and §8
/// (this surface, and the two-object invariant).
///
/// it. `loadNotes()` already reads only the Markdown, so this is ordering a
/// two-sided change inside one PR, not a compatibility layer.
enum CorpusStore {
    nonisolated(unsafe) static var rootOverride: URL?
    private static let configuredRootKey = "sessionArchiveRootPath"
    private static let inboxSlug = "inbox"
    private static let log = Logger(subsystem: "CueMe", category: "CorpusStore")

    static var rootURL: URL {
        if let rootOverride { return rootOverride }
        if let path = UserDefaults.standard.string(forKey: configuredRootKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CueMe/Session Archive", isDirectory: true)
    }

    static func setRoot(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: configuredRootKey)
    }

    // MARK: - Location

    static func noteURL(for note: MemoryNote) -> URL {
        rootURL.appendingPathComponent(parentDirectory(of: note), isDirectory: true)
            .appendingPathComponent("\(note.archiveFolderName).md")
    }

    static func noteFolder(for note: MemoryNote) -> URL {
        rootURL.appendingPathComponent(parentDirectory(of: note), isDirectory: true)
            .appendingPathComponent(note.archiveFolderName, isDirectory: true)
    }

    /// Reserves a `raw/` directory for a note that does not exist as a
    /// `MemoryNote` value yet — a live recording only has an id and a start
    /// time. The slug is deterministic from `startedAt` alone (design.md's
    /// untitled-session convention), so a later `save()` of the eventually
    /// constructed note resolves to the same location without any explicit
    /// threading, as long as it goes through `resolvingLocation(_:)` first.
    @discardableResult
    static func prepareNote(id: UUID, startedAt: Date, under parent: MemoryNote?) -> URL? {
        let parentDir = parent.map(childDirectory(of:)) ?? ""
        let slug = OKFBundle.untitledSlug(startedAt: startedAt)
        let raw = rootURL.appendingPathComponent(parentDir, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent(OKFBundle.rawDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
            return raw
        } catch {
            return nil
        }
    }

    /// Resolves where `note` belongs: unchanged when a `.md` already exists at
    /// its current location (idempotent re-save), otherwise placed fresh under
    /// the default inbox note. A note explicitly renamed by the user
    /// (`titleSource == .user`) gets a title-based slug; everything else gets
    /// the untitled, date-based slug (design.md §1) so a generated title never
    /// causes file churn. Callers that need to know a not-yet-saved note's
    /// folder — to write audio into `raw/` before the first `save()` — call
    /// this first so every lookup agrees.
    static func resolvingLocation(_ note: MemoryNote) -> MemoryNote {
        var note = note
        guard !isPlaced(note) else { return note }
        let parent = defaultInboxNote()
        let parentDir = childDirectory(of: parent)
        note.relativeFolderPath = parentDir
        if note.titleSource == .user {
            note.archiveFolderName = OKFBundle.uniqueSlug(note.title, taken: takenSlugs(in: parentDir))
        } else {
            note.archiveFolderName = OKFBundle.untitledSlug(startedAt: note.startedAt)
        }
        return note
    }

    /// The root-level note new sessions are born under (decision recorded in
    /// `specs/okf-corpus/tasks/T013-corpus-store.md`), created the first time
    /// it is needed if it does not already exist.
    static func defaultInboxNote() -> MemoryNote {
        let url = rootURL.appendingPathComponent("\(inboxSlug).md")
        if let markdown = try? String(contentsOf: url, encoding: .utf8),
           var note = NoteDocumentReader.parse(
               markdown, slug: inboxSlug, turns: NoteTree.declaredTranscriptTurnCount(in: markdown)
           ) {
            note.relativeFolderPath = ""
            note.archiveFolderName = inboxSlug
            return note
        }
        var note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 0),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: "Inbox",
            noteKind: .note,
            titleSource: .user
        )
        note.relativeFolderPath = ""
        note.archiveFolderName = inboxSlug
        writeNoteDocument(note)
        return note
    }

    // MARK: - Save / load / delete

    @discardableResult
    static func save(_ note: MemoryNote) -> URL? {
        writeNoteDocument(resolvingLocation(note))
    }

    /// Walks the tree from the root, reading only `.md` files and never
    /// `raw/` (AC1). A folder without a sibling note is logged, not
    /// swallowed; its children still load (AC2).
    static func loadNotes() -> [MemoryNote] {
        let result = NoteTree.discover(at: rootURL, reading: DiskNoteTreeReading())
        if !result.orphanFolders.isEmpty {
            log.notice(
                "orphan folders without a sibling note: \(result.orphanFolders.joined(separator: ", "), privacy: .public)"
            )
        }
        return result.notes
    }

    /// Fills in a note's transcript from `raw/transcript.md` on demand.
    /// A no-op when already loaded, and when there is nothing on disk to load.
    static func loadTranscript(for note: MemoryNote) -> MemoryNote {
        var note = note
        guard !note.transcript.isLoaded else { return note }
        let url = noteFolder(for: note).appendingPathComponent(OKFBundle.transcriptRelativePath)
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return note }
        note.transcript = .loaded(TranscriptDocument.parse(markdown))
        return note
    }

    /// Removes the note's `.md`, its sibling folder (and everything nested
    /// under it — `raw/` and every child, AC6), then cleans up the parent's
    /// sibling folder if that was its last remaining child (AC3).
    static func delete(_ note: MemoryNote) {
        try? FileManager.default.removeItem(at: noteURL(for: note))
        try? FileManager.default.removeItem(at: noteFolder(for: note))
        removeParentFolderIfNowEmpty(note)
    }

    // MARK: - Private

    @discardableResult
    private static func writeNoteDocument(_ note: MemoryNote) -> URL? {
        let folder = noteFolder(for: note)
        let parentDirectoryURL = rootURL.appendingPathComponent(parentDirectory(of: note), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
            try NoteDocumentWriter.render(note).write(to: noteURL(for: note), atomically: true, encoding: .utf8)
            if let transcriptMarkdown = TranscriptDocument.render(note) {
                let rawDirectory = folder.appendingPathComponent(OKFBundle.rawDirectoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
                try transcriptMarkdown.write(
                    to: folder.appendingPathComponent(OKFBundle.transcriptRelativePath),
                    atomically: true,
                    encoding: .utf8
                )
            }
            return noteURL(for: note)
        } catch {
            return nil
        }
    }

    private static func isPlaced(_ note: MemoryNote) -> Bool {
        FileManager.default.fileExists(atPath: noteURL(for: note).path)
    }

    private static func parentDirectory(of note: MemoryNote) -> String {
        safeRelativePath(note.relativeFolderPath) ?? ""
    }

    /// Where `note`'s own children live: its parent directory plus its own
    /// slug — i.e. the relative path to `noteFolder(for: note)`.
    private static func childDirectory(of note: MemoryNote) -> String {
        let parentDir = parentDirectory(of: note)
        return parentDir.isEmpty ? note.archiveFolderName : "\(parentDir)/\(note.archiveFolderName)"
    }

    private static func safeRelativePath(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.hasPrefix("/") { return nil }
        if value.split(separator: "/").contains("..") { return nil }
        return value
    }

    private static func takenSlugs(in parentDir: String) -> Set<String> {
        let directory = rootURL.appendingPathComponent(parentDir, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(entries.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) })
    }

    private static func removeParentFolderIfNowEmpty(_ note: MemoryNote) {
        let parentDir = parentDirectory(of: note)
        guard !parentDir.isEmpty else { return }
        let parentFolderURL = rootURL.appendingPathComponent(parentDir, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parentFolderURL.path),
              entries.isEmpty else { return }
        try? FileManager.default.removeItem(at: parentFolderURL)
    }
}
