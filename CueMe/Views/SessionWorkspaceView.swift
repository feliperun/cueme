import SwiftUI

struct SessionWorkspaceView: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote
    @State private var tab: SessionWorkspaceTab
    @State private var player = MeetingPlayer()
    @State private var waveform = WaveformLoader()
    @State private var editor = NoteEditorState()

    init(record: MemoryNote) {
        self.record = record
        _tab = State(initialValue: record.origin == .written ? .note : .review)
    }

    var body: some View {
        VStack(spacing: 0) {
            NoteWorkspaceHeaderBar(record: record, selection: $tab, editor: editor)
            if isCapturingLive { LiveStrip() }
            if record.containsRecording {
                WaveformPlayerView(player: player, envelope: waveform.envelope, loading: waveform.isLoading)
                    .padding(.horizontal, 26).padding(.vertical, 10)
                    .background(Theme.paper)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
            }
            // No `.id(tab)` here: an explicit identity freezes the pane's inputs,
            // so a note edited (or swapped) underneath it kept rendering the
            // previous record. The `switch` in `SessionWorkspacePane` already
            // gives each projection its own identity.
            SessionWorkspacePane(record: record, selection: tab, player: player, editor: editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AskCueMeBar(record: record, tab: $tab)
        }
        .background(Theme.paper)
        .task(id: record.id) {
            editor.reset()
            await waveform.load(for: record, into: player)
        }
        .onDisappear { player.teardown() }
    }

    private var isCapturingLive: Bool {
        app.isRunning && app.currentSessionID == record.id
    }
}
