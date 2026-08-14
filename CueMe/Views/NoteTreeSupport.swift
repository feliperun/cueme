import SwiftUI

/// Which built-in section of the tree is driving the note list.
enum LibrarySection: Equatable { case all, inbox, journal }

/// The sidebar tree is the corpus tree: there is no project entity, so
/// "belongs to" is simply where a note sits, and every relationship the tree
/// draws comes from the path.
enum NoteTreeProjection {
    /// A note's own directory — where its children live.
    static func subtreePath(of note: MemoryNote) -> String {
        let parent = note.relativeFolderPath ?? ""
        return parent.isEmpty ? note.archiveFolderName : "\(parent)/\(note.archiveFolderName)"
    }

    static func rootNotes(in history: [MemoryNote]) -> [MemoryNote] {
        history
            .filter { ($0.relativeFolderPath ?? "").isEmpty }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Direct children only — the tree draws one level at a time.
    static func children(in history: [MemoryNote], of note: MemoryNote) -> [MemoryNote] {
        let directory = subtreePath(of: note)
        return history
            .filter { ($0.relativeFolderPath ?? "") == directory }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Everything nested under a note, at any depth, including itself. This is
    /// what scopes the note list when a tree node is selected.
    static func subtree(in history: [MemoryNote], of note: MemoryNote) -> [MemoryNote] {
        let directory = subtreePath(of: note)
        return history.filter { candidate in
            if candidate.id == note.id { return true }
            let parent = candidate.relativeFolderPath ?? ""
            return parent == directory || parent.hasPrefix(directory + "/")
        }
    }

    static func hasChildren(in history: [MemoryNote], of note: MemoryNote) -> Bool {
        !children(in: history, of: note).isEmpty
    }

    static func showsLiveChild(for noteID: UUID, activeParentNoteID: UUID?, isRunning: Bool) -> Bool {
        isRunning && activeParentNoteID == noteID
    }
}

@MainActor
extension AppModel {
    /// Tree → select a built-in section (Inbox / All notes / Journal).
    func selectLibrarySection(_ section: LibrarySection) {
        librarySection = section
        librarySubtreeNoteID = nil
        activeParentNoteID = nil
        libraryLabelFilter = nil
        historyTypeFilter = .all
    }

    /// Tree → scope the list to a note and everything under it.
    func selectLibraryNote(_ id: UUID) {
        librarySection = .all
        librarySubtreeNoteID = id
        activeParentNoteID = id
        libraryLabelFilter = nil
        historyTypeFilter = .all
    }

    /// One projection per render keeps semantic search, snippets and tab counts
    /// on the same result set instead of querying the index once per control.
    var noteListProjection: NoteListProjection {
        NoteListProjection(
            history: history,
            searchResults: historySearchResults(typeFilter: .all),
            section: librarySection,
            selectedType: historyTypeFilter
        )
    }

    var rootNotes: [MemoryNote] { NoteTreeProjection.rootNotes(in: history) }

    /// Children shown under a tree node always come from the complete archive,
    /// never from the currently searched or type-filtered note list.
    func noteTreeChildren(of note: MemoryNote) -> [MemoryNote] {
        NoteTreeProjection.children(in: history, of: note)
    }

    func noteSubtree(of id: UUID) -> [MemoryNote] {
        guard let note = history.first(where: { $0.id == id }) else { return [] }
        return NoteTreeProjection.subtree(in: history, of: note)
    }

    func isNoteForcedExpanded(_ note: MemoryNote) -> Bool {
        if librarySubtreeNoteID == note.id { return true }
        if let selected = selectedSession,
           NoteTreeProjection.subtree(in: history, of: note).contains(where: { $0.id == selected.id }),
           selected.id != note.id {
            return true
        }
        return NoteTreeProjection.showsLiveChild(
            for: note.id, activeParentNoteID: activeParentNoteID, isRunning: isRunning
        )
    }

    func isNoteExpanded(_ note: MemoryNote, explicitly expandedNoteIDs: Set<UUID>) -> Bool {
        expandedNoteIDs.contains(note.id) || isNoteForcedExpanded(note)
    }

    func selectNoteTreeRecord(_ record: MemoryNote) {
        let parent = record.relativeFolderPath ?? ""
        if let container = history.first(where: { NoteTreeProjection.subtreePath(of: $0) == parent }) {
            selectLibraryNote(container.id)
        }
        historySearch = ""
        historyDateFilter = .all
        selectSession(record.id)
    }

    /// Tree → drop a dragged note onto another (or onto the root when nil).
    ///
    /// The projection is only updated once the store confirms the move: the
    /// sidebar must never show a shape the filesystem does not have.
    func dropNote(_ draggedID: UUID, onto targetID: UUID?) {
        let outcome = NoteTreeMove.apply(dragging: draggedID, onto: targetID, in: history) {
            CorpusStore.move($0, under: $1)
        }
        history = outcome.history
        noteTreeWarning = outcome.warning
        draggingNoteID = nil
        guard outcome.warning == nil, let moved = outcome.history.first(where: { $0.id == draggedID }) else { return }
        let destination = targetID.flatMap { id in history.first { $0.id == id } }
        recordStructuralChange(
            .moved,
            "\(CorpusLogDocument.link(moved.title, path: NoteTreeProjection.subtreePath(of: moved) + ".md")) movida para "
                + (destination.map { CorpusLogDocument.link($0.title, path: NoteTreeProjection.subtreePath(of: $0) + ".md") }
                    ?? "a raiz do corpus") + "."
        )
    }

    func acceptsNoteDrop(onto targetID: UUID?) -> Bool {
        guard let draggingNoteID else { return false }
        return NoteDropTarget.accepts(dragging: draggingNoteID, onto: targetID, in: history)
    }

    /// Stable, distinct accent for a tree dot (violet / mint / amber / cyan).
    func libraryColor(for noteID: UUID?) -> Color {
        guard let noteID, let index = rootNotes.firstIndex(where: { $0.id == noteID }) else { return Theme.faint }
        let palette: [Color] = [Theme.violet, Theme.mint, Theme.amber, Theme.cyan]
        return palette[index % palette.count]
    }
}
