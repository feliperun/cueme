import SwiftUI

/// Which built-in section of the tree is driving the note list.
enum LibrarySection: Equatable { case all, inbox, journal }

enum ProjectTreeProjection {
    static func records(in history: [SessionRecord], projectID: UUID) -> [SessionRecord] {
        history
            .filter { $0.projectID == projectID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func showsLiveChild(for projectID: UUID, activeProjectID: UUID?, isRunning: Bool) -> Bool {
        isRunning && activeProjectID == projectID
    }
}

@MainActor
extension AppModel {
    /// Tree → select a built-in section (Inbox / All notes / Journal).
    func selectLibrarySection(_ section: LibrarySection) {
        librarySection = section
        libraryProjectFilterID = nil
        activeProjectID = nil
        libraryLabelFilter = nil
        historyTypeFilter = .all
    }

    /// Tree → select a project folder.
    func selectLibraryProject(_ id: UUID) {
        librarySection = .all
        libraryProjectFilterID = id
        activeProjectID = id
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

    /// Records nested under a project in the tree always come from the complete
    /// archive, never from the currently searched or type-filtered note list.
    func projectTreeRecords(for projectID: UUID) -> [SessionRecord] {
        ProjectTreeProjection.records(in: history, projectID: projectID)
    }

    func isProjectForcedExpanded(_ projectID: UUID) -> Bool {
        libraryProjectFilterID == projectID
            || selectedSession?.projectID == projectID
            || ProjectTreeProjection.showsLiveChild(
                for: projectID,
                activeProjectID: activeProjectID,
                isRunning: isRunning
            )
    }

    func isProjectExpanded(_ projectID: UUID, explicitly expandedProjectIDs: Set<UUID>) -> Bool {
        expandedProjectIDs.contains(projectID)
            || isProjectForcedExpanded(projectID)
    }

    func selectProjectTreeRecord(_ record: SessionRecord) {
        guard let projectID = record.projectID else { return }
        selectLibraryProject(projectID)
        historySearch = ""
        historyDateFilter = .all
        selectSession(record.id)
    }

    /// Stable, distinct accent for a project dot (violet / mint / amber / cyan cycle).
    func libraryColor(for projectID: UUID?) -> Color {
        guard let projectID,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return Theme.faint }
        let palette: [Color] = [Theme.violet, Theme.mint, Theme.amber, Theme.cyan]
        return palette[index % palette.count]
    }
}
