import SwiftUI

/// Switches the workspace body to the pane the selected tab names. Split out of
/// `SessionWorkspaceNavigation` so the tab bar and the pane it selects are not
/// the same file.
struct SessionWorkspacePane: View {
    let record: MemoryNote
    let selection: SessionWorkspaceTab
    let player: MeetingPlayer
    let editor: NoteEditorState

    @ViewBuilder
    var body: some View {
        switch selection {
        case .note: MemoryNoteEditor(record: record, editor: editor)
        case .review: SessionReviewPane(record: record, player: player)
        case .coach: SessionCoachPane(record: record)
        case .summary: SessionSummaryPane(record: record)
        case .transcript: SessionTranscriptPane(record: record, player: player)
        case .notes: SessionNotesPane(record: record, player: player)
        case .takeaways: SessionTakeawaysPane(record: record)
        case .generated: SessionArtifactsPane(record: record)
        }
    }
}
