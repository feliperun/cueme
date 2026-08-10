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

    // MARK: - Move and rename

    /// Result of a structural change, so the caller can report what happened
    /// rather than guess. T018 routes these into the corpus `log.md`.
    struct RelocationOutcome {
        let note: MemoryNote
        let fromPath: String
        let toPath: String
        let rewrittenDocuments: Int
    }

    /// Moves `note` — and everything under it — to live under `parent`, or to
    /// the corpus root when `parent` is nil.
    ///
    /// A note is two filesystem objects: `<slug>.md` and, conditionally,
    /// `<slug>/`. They move folder-first, and the folder is put back if the
    /// file step fails, so a partial move never strands a subtree away from
    /// its document.
    @discardableResult
    static func move(_ note: MemoryNote, under parent: MemoryNote?) -> RelocationOutcome? {
        let destinationDir = parent.map(childDirectory(of:)) ?? ""
        guard canPlace(note, in: destinationDir) else { return nil }
        return relocate(note, toParentDirectory: destinationDir, slug: slugFor(note.title, in: destinationDir, movingFrom: note))
    }

    /// Renames `note`, moving its document and folder to the new slug and
    /// rewriting the links that pointed at the old path.
    ///
    /// This is the explicit user rename. A title generated during
    /// post-processing goes through `applyGeneratedTitle` and `save`, which
    /// leaves an already-placed note exactly where it is — letting generated
    /// titles churn files would rewrite links on every summary pass.
    @discardableResult
    static func rename(_ note: MemoryNote, to title: String) -> RelocationOutcome? {
        var renamed = note
        renamed.rename(to: title)
        let parentDir = parentDirectory(of: note)
        return relocate(renamed, toParentDirectory: parentDir, slug: slugFor(renamed.title, in: parentDir, movingFrom: note))
    }

    /// The note's own slug only frees itself up when it is staying in the same
    /// directory. Moving somewhere else, an identically named sibling there is
    /// a real collision and has to be disambiguated.
    private static func slugFor(_ title: String, in destinationDir: String, movingFrom note: MemoryNote) -> String {
        var taken = takenSlugs(in: destinationDir)
        if destinationDir == parentDirectory(of: note) { taken.remove(note.archiveFolderName) }
        return OKFBundle.uniqueSlug(title, taken: taken)
    }

    /// True when `note` may be placed in `destinationDir`: a note cannot be
    /// moved inside its own subtree, which would detach it from the corpus.
    static func canPlace(_ note: MemoryNote, in destinationDir: String) -> Bool {
        let own = childDirectory(of: note)
        return destinationDir != own && !destinationDir.hasPrefix(own + "/")
    }

    private static func relocate(
        _ note: MemoryNote,
        toParentDirectory destinationDir: String,
        slug: String
    ) -> RelocationOutcome? {
        let fromDocument = noteURL(for: note)
        let fromFolder = noteFolder(for: note)
        let fromPath = documentPath(parentDir: parentDirectory(of: note), slug: note.archiveFolderName)

        var moved = note
        moved.archiveFolderName = slug
        moved.relativeFolderPath = destinationDir.isEmpty ? nil : destinationDir
        moved.modifiedAt = Date()

        let toDocument = noteURL(for: moved)
        let toFolder = noteFolder(for: moved)
        let toPath = documentPath(parentDir: destinationDir, slug: slug)
        guard fromDocument.standardizedFileURL != toDocument.standardizedFileURL else {
            return RelocationOutcome(note: note, fromPath: fromPath, toPath: toPath, rewrittenDocuments: 0)
        }

        do {
            try FileManager.default.createDirectory(
                at: toDocument.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try moveNoteObjects(document: (fromDocument, toDocument), folder: (fromFolder, toFolder))
        } catch {
            log.error("relocate failed for \(fromPath, privacy: .public)")
            return nil
        }

        let rewritten = BacklinkIndex.rewriteReferences(from: fromPath, to: toPath, in: rootURL, excluding: toDocument)
        _ = writeNoteDocument(moved)
        removeParentFolderIfNowEmpty(note)
        log.notice("relocated \(fromPath, privacy: .public) -> \(toPath, privacy: .public), \(rewritten) documents rewritten")
        return RelocationOutcome(note: moved, fromPath: fromPath, toPath: toPath, rewrittenDocuments: rewritten)
    }

    /// Moves a note's two filesystem objects, folder first. If the document
    /// step fails the folder is put back, so a half-move never strands a
    /// subtree away from the document that names it.
    ///
    /// `moving` is a parameter so the failure path can be exercised: with a
    /// correct slug rule the second step only fails on real I/O errors, which
    /// a test cannot provoke on demand.
    static func moveNoteObjects(
        document: (from: URL, to: URL),
        folder: (from: URL, to: URL),
        moving: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) throws {
        let hadFolder = FileManager.default.fileExists(atPath: folder.from.path)
        if hadFolder { try moving(folder.from, folder.to) }
        do {
            try moving(document.from, document.to)
        } catch {
            if hadFolder { try? moving(folder.to, folder.from) }
            throw error
        }
    }

    /// Bundle-relative path of a note's document, the form links use.
    static func documentPath(parentDir: String, slug: String) -> String {
        parentDir.isEmpty ? "/\(slug).md" : "/\(parentDir)/\(slug).md"
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
