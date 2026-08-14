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
    /// A different root is a different corpus, so the legacy verdict from the
    /// previous one does not carry over.
    nonisolated(unsafe) static var rootOverride: URL? {
        didSet { isReadOnly = false }
    }

    /// Set when the chosen archive still holds a pre-OKF layout. Every write is
    /// refused while it is on: a save would drop everything that still lives
    /// only in `session.json`.
    nonisolated(unsafe) private(set) static var isReadOnly = false

    /// Re-answers "has this archive been migrated?" for the current root, and
    /// returns the verdict. Called when the app opens a corpus, not per save —
    /// it walks the tree.
    @discardableResult
    static func refreshLegacyGuard() -> Bool {
        isReadOnly = holdsLegacyArchive()
        return isReadOnly
    }

    private static let configuredRootKey = "sessionArchiveRootPath"
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
        isReadOnly = false
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
        let url = rootURL.appendingPathComponent("\(OKFBundle.inboxSlug).md")
        if let markdown = try? String(contentsOf: url, encoding: .utf8),
           var note = NoteDocumentReader.parse(
               markdown, slug: OKFBundle.inboxSlug, turns: NoteTree.declaredTranscriptTurnCount(in: markdown)
           ) {
            note.relativeFolderPath = ""
            note.archiveFolderName = OKFBundle.inboxSlug
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
        note.archiveFolderName = OKFBundle.inboxSlug
        writeNoteDocument(note)
        return note
    }

    // MARK: - Save / load / delete

    /// Writes the note's `.md` and, unless told otherwise, its transcript.
    ///
    /// A live snapshot passes `includingTranscript: false`: re-rendering
    /// hundreds of turns every few seconds is the cost T019 exists to remove,
    /// and `appendTranscript` has already put the new ones on disk. The final
    /// save at session end renders the whole thing.
    @discardableResult
    static func save(_ note: MemoryNote, includingTranscript: Bool = true) -> URL? {
        guard !isReadOnly else {
            log.error("refused to write: the archive has not been migrated yet")
            return nil
        }
        return writeNoteDocument(resolvingLocation(note), includingTranscript: includingTranscript)
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
        return result.notes.sorted { $0.startedAt > $1.startedAt }
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
        MeetingRecording.deleteLegacy(for: note.id)
    }

    /// Deleting by id still has to reach the pre-corpus audio directory, which
    /// is keyed by id alone, even when no note carries it any more.
    static func delete(_ id: UUID) {
        if let note = loadNotes().first(where: { $0.id == id }) {
            delete(note)
        } else {
            MeetingRecording.deleteLegacy(for: id)
        }
    }

    // MARK: - Live transcript append

    /// Appends the given turns to `raw/transcript.md` without rewriting what is
    /// already there, and returns the ids actually written.
    ///
    /// The invariant that lets this exist: N successive appends produce bytes
    /// identical to one full render of the same N turns. `renderTurnBlocks` is
    /// the single grammar both paths use, and the separator between blocks is
    /// reproduced here — the file ends with a newline, so the append reclaims
    /// that byte before writing `\n\n<block>\n`.
    ///
    /// Only the new turns are needed, so this works while `note.transcript` is
    /// still `.notLoaded`: appending never requires reading the old turns back.
    @discardableResult
    static func appendTranscript(_ lines: [TranscriptLine], to note: MemoryNote) -> [UUID] {
        let finals = lines.filter(\.isFinal)
        guard !finals.isEmpty else { return [] }
        let url = noteFolder(for: note).appendingPathComponent(OKFBundle.transcriptRelativePath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            var seed = note
            seed.transcript = .loaded(finals)
            guard let document = TranscriptDocument.render(seed) else { return [] }
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try document.write(to: url, atomically: true, encoding: .utf8)
                return finals.map(\.id)
            } catch {
                log.error("transcript seed failed")
                return []
            }
        }

        let blocks = TranscriptDocument.renderTurnBlocks(
            finals, startedAt: note.audioTimelineStart, participantNames: note.participantNames
        )
        guard let payload = "\n\n\(blocks)\n".data(using: .utf8) else { return [] }
        do {
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            // Trim every trailing newline before writing the separator. The
            // file may end with the last turn, or — when no turn has been
            // written yet — with the section heading; both have to produce the
            // single blank line a full render puts between blocks.
            var end = try handle.seekToEnd()
            while end > 0 {
                try handle.seek(toOffset: end - 1)
                guard try handle.read(upToCount: 1) == Data("\n".utf8) else { break }
                end -= 1
            }
            try handle.truncate(atOffset: end)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            return finals.map(\.id)
        } catch {
            log.error("transcript append failed")
            return []
        }
    }

    // MARK: - Legacy archive guard

    /// True when the root still holds a pre-OKF archive: a `session.json`, or a
    /// `note.md` inside a note folder.
    ///
    /// This is not a compatibility path — ADR 0043 forbids those, and ADR 0049
    /// makes the migration a one-shot external script. It is a stop: an
    /// unmigrated archive still keeps transcripts, coach cards, minutes and
    /// evidence in `session.json`, which this build no longer reads. Writing to
    /// it would drop all of that on the first save, and auto-update means the
    /// user never chose the moment. So the app reads nothing and writes
    /// nothing until the migration has run.
    static func holdsLegacyArchive(at root: URL? = nil) -> Bool {
        let base = root ?? rootURL
        guard let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in walker {
            if url.lastPathComponent == "session.json" { return true }
            if url.lastPathComponent == "note.md" { return true }
        }
        return false
    }

    // MARK: - Change detection

    /// Newest mtime among the corpus `.md` files, or nil when there are none.
    /// Stat only — nothing is read.
    static func latestModification() -> Date? {
        guard let walker = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: Date?
        for case let url as URL in walker where url.pathExtension == "md" {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ), values.isRegularFile == true, let date = values.contentModificationDate else { continue }
            if newest == nil || date > newest! { newest = date }
        }
        return newest
    }

    /// True when any `.md` in the corpus is newer than `stamp`, or when there is
    /// no stamp yet. A load that would read nothing new is skipped entirely.
    static func corpusChanged(since stamp: Date?) -> Bool {
        guard let stamp else { return true }
        guard let newest = latestModification() else { return false }
        return newest > stamp
    }

    // MARK: - Reserved files

    /// Regenerates every `index.md` the tree needs, and returns the relative
    /// paths actually written.
    ///
    /// Called once per batch, never per save, and a level whose rendered bytes
    /// are unchanged is skipped — otherwise every load would show up as a diff.
    @discardableResult
    static func writeIndexes(for notes: [MemoryNote]) -> [String] {
        var directories = Set(notes.map { $0.relativeFolderPath ?? "" })
        directories.insert("")
        var written: [String] = []

        for directory in directories.sorted() {
            let entries = IndexDocument.entries(in: notes, directory: directory)
            guard !entries.isEmpty else { continue }
            let heading = directory.isEmpty
                ? IndexDocument.rootHeading
                : notes.first { NoteTreeProjection.subtreePath(of: $0) == directory }?.title
                    ?? (directory as NSString).lastPathComponent
            let rendered = IndexDocument.render(heading: heading, entries: entries, isRoot: directory.isEmpty)
            let relative = directory.isEmpty
                ? OKFBundle.indexFileName
                : "\(directory)/\(OKFBundle.indexFileName)"
            let url = rootURL.appendingPathComponent(relative)
            if (try? String(contentsOf: url, encoding: .utf8)) == rendered { continue }
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try rendered.write(to: url, atomically: true, encoding: .utf8)
                written.append(relative)
            } catch {
                log.error("index write failed for \(relative, privacy: .public)")
            }
        }
        return written
    }

    /// Appends one structural event to the root `log.md`.
    static func appendLog(
        _ sentence: String,
        operation: CorpusLogDocument.Operation,
        on date: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        let url = rootURL.appendingPathComponent(OKFBundle.logFileName)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let updated = CorpusLogDocument.appending(
            sentence, operation: operation, on: date, to: existing, timeZone: timeZone
        )
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("log append failed")
        }
    }

    /// Writes the corpus `AGENTS.md`, and only if it is absent. Returns true
    /// when it was created. The user's edits to it are theirs to keep.
    @discardableResult
    static func writeAgentsFileIfAbsent() -> Bool {
        let url = rootURL.appendingPathComponent(OKFBundle.agentsFileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try CorpusAgentsDocument.content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            log.error("AGENTS.md write failed")
            return false
        }
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
        return place(note, inParentDirectory: destinationDir, slug: slugFor(note.title, in: destinationDir, movingFrom: note))
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
        return place(renamed, inParentDirectory: parentDir, slug: slugFor(renamed.title, in: parentDir, movingFrom: note))
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

    private static func place(
        _ note: MemoryNote,
        inParentDirectory destinationDir: String,
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
            log.error("move failed for \(fromPath, privacy: .public)")
            return nil
        }

        let rewritten = BacklinkIndex.rewriteReferences(from: fromPath, to: toPath, in: rootURL, excluding: toDocument)
        _ = writeNoteDocument(moved)
        removeParentFolderIfNowEmpty(note)
        log.notice("moved \(fromPath, privacy: .public) -> \(toPath, privacy: .public), \(rewritten) documents rewritten")
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
    private static func writeNoteDocument(_ note: MemoryNote, includingTranscript: Bool = true) -> URL? {
        let folder = noteFolder(for: note)
        let parentDirectoryURL = rootURL.appendingPathComponent(parentDirectory(of: note), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
            try NoteDocumentWriter.render(note).write(to: noteURL(for: note), atomically: true, encoding: .utf8)
            if includingTranscript, let transcriptMarkdown = TranscriptDocument.render(note) {
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
