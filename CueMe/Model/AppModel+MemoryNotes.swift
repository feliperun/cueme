import Foundation

@MainActor
extension AppModel {
    var allLabels: [String] {
        Array(Set(history.flatMap(\.labels))).sorted()
    }

    func liveSessionBrief() -> SessionBrief {
        var snapshot = brief
        snapshot.relevantMemoryContext = usePersonalMemoryInCoach
            ? RelevantMemoryContextBuilder.build(for: brief, records: history)
            : nil
        return snapshot
    }

    /// `force` is the user asking explicitly, which skips the mtime shortcut —
    /// clicking refresh and getting nothing because a clock disagreed would be
    /// worse than the reread it avoids. It does not open the UI-test guard: a
    /// deterministic fixture must never be replaced by an empty archive.
    func reloadWorkspaceFromDisk(force: Bool = false) {
        guard !isSessionBusy else { return }
        guard reloadFromDiskEnabled else { return }
        // Activation fires this every time. Stat the tree first: when no `.md`
        // is newer than the last load, there is nothing to read.
        guard force || CorpusStore.corpusChanged(since: lastCorpusLoad) else { return }
        lastCorpusLoad = CorpusStore.latestModification()
        history = CorpusStore.loadNotes()
        CorpusStore.writeIndexes(for: history)
        if let selectedSessionID, !history.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
    }

    @discardableResult
    func createMemoryNote(kind: MemoryNoteKind = .note) -> UUID {
        let now = Date()
        let initialTitle: String
        switch kind {
        case .journal:
            initialTitle = "Diário · \(now.formatted(date: .abbreviated, time: .omitted))"
        case .note:
            initialTitle = "Nota sem título"
        default:
            initialTitle = kind.label
        }
        var note = MemoryNote(
            startedAt: now,
            endedAt: now,
            mode: .recording,
            training: false,
            conversationLang: brief.nativeLang,
            nativeLang: brief.nativeLang,
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: initialTitle,
            noteKind: kind,
            markdownBody: "",
            titleSource: .fallback
        )
        // Born under the selected tree node, or under `inbox` when none is.
        note = CorpusStore.resolvingLocation(note)
        CorpusStore.save(note)
        if let parent = activeParentNoteID.flatMap({ id in history.first { $0.id == id } }),
           let moved = CorpusStore.move(note, under: parent) {
            note = moved.note
        }
        replaceHistoryRecord(note)
        selectedSessionID = note.id
        recordStructuralChange(
            .created,
            "\(CorpusLogDocument.link(note.title, path: NoteTreeProjection.subtreePath(of: note) + ".md")) criada."
        )
        return note.id
    }

    /// An explicit rename is a structural event: the document and its sibling
    /// folder move to the new slug and every inbound link is rewritten. A title
    /// generated during post-processing goes through `save` instead, which
    /// leaves the file where it is.
    func renameMemoryNote(_ id: UUID, to title: String) {
        guard let note = history.first(where: { $0.id == id }) else { return }
        guard let outcome = CorpusStore.rename(note, to: title) else {
            mutateRecord(id) { $0.rename(to: title) }
            return
        }
        replaceHistoryRecord(outcome.note)
        recordStructuralChange(
            .renamed,
            "\(CorpusLogDocument.link(outcome.note.title, path: outcome.toPath)) renomeada de "
                + "`\(note.archiveFolderName)`; \(outcome.rewrittenDocuments) páginas com links atualizados."
        )
    }

    /// Logs a durable structural event and refreshes the reserved files. Called
    /// once per change, never per keystroke — `log.md` is a history of the
    /// corpus, not a keystroke journal.
    func recordStructuralChange(_ operation: CorpusLogDocument.Operation, _ sentence: String) {
        CorpusStore.appendLog(sentence, operation: operation)
        CorpusStore.writeIndexes(for: history)
    }

    func updateMarkdownBody(_ id: UUID, body: String) {
        mutateRecord(id) { $0.markdownBody = body }
    }

    func addLabel(_ rawLabel: String, to id: UUID) {
        mutateRecord(id) { note in
            note.setLabels(note.labels + [rawLabel])
        }
    }

    func removeLabel(_ label: String, from id: UUID) {
        mutateRecord(id) { note in
            note.setLabels(note.labels.filter { $0 != label })
        }
    }

    func addAttachment(from source: URL, to id: UUID) throws {
        guard let note = history.first(where: { $0.id == id }) else { return }
        let secured = source.startAccessingSecurityScopedResource()
        defer { if secured { source.stopAccessingSecurityScopedResource() } }
        let attachments = CorpusStore.noteFolder(for: note)
            .appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let filename = uniqueFilename(source.lastPathComponent, in: attachments)
        try FileManager.default.copyItem(at: source, to: attachments.appendingPathComponent(filename))
        mutateRecord(id) { record in
            record.attachments.append(.init(filename: "attachments/\(filename)", kind: attachmentKind(source)))
        }
    }

    private func uniqueFilename(_ original: String, in directory: URL) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func attachmentKind(_ url: URL) -> NoteAttachmentKind {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp3", "wav", "aif", "aiff", "caf": return .audio
        case "png", "jpg", "jpeg", "heic", "gif": return .image
        case "pdf", "md", "txt", "doc", "docx": return .document
        default: return .file
        }
    }
}
