import SwiftUI

/// Note-first three-column shell: project tree · note list · note surface.
/// The note column is the old workspace body; live is a *state* of the note
/// column (selectedSession == nil), never a separate destination.
struct RootWorkspaceShell: View {
    var body: some View {
        HStack(spacing: 0) {
            ProjectTreeColumn()
            Divider().opacity(0.45)
            NoteListColumn()
            Divider().opacity(0.45)
            NoteColumn()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteColumn: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            if let record = app.selectedSession {
                SessionWorkspaceView(record: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LiveWorkspace()
            }
        }
        .background(Theme.paper)
    }
}

private struct LiveWorkspace: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            CaptureHealthAlert()

            if isPristineIdle {
                SessionLaunchView()
                    .frame(maxHeight: .infinity)
            } else if app.isRunning, !app.brief.mode.isPassive {
                // Live capture as a note state: dedicated coach-hero layout.
                LiveNoteView()
                    .frame(maxHeight: .infinity)
            } else if app.brief.mode.isPassive {
                MeetingPanel()
                    .frame(maxHeight: .infinity)
                if app.sessionStartTime != nil {
                    LiveTransportBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                // Stopped, non-passive, with content — review before it's saved.
                QuestionBanner()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                CoachingPane()
                    .frame(maxHeight: .infinity)
                CollapsiblePanels()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.24), value: app.sessionStartTime != nil)
    }

    private var isPristineIdle: Bool {
        app.sessionState == .idle && app.transcript.isEmpty && app.coachCards.isEmpty
    }
}
