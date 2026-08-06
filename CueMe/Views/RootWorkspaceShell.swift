import SwiftUI
import AppKit

/// Note-first three-column shell: project tree · note list · note surface.
/// The note column is the old workspace body; live is a *state* of the note
/// column (selectedSession == nil), never a separate destination.
struct RootWorkspaceShell: View {
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTitlebar()
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
}

private struct WorkspaceTitlebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 10) {
                Spacer()
                if app.isRunning || app.sessionState == .preparing {
                    LiveHealthStrip()
                }
                if app.isRunning, let started = app.sessionStartTime {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Theme.amber)
                            .frame(width: 7, height: 7)
                            .modifier(TitlebarRecordingPulse())
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text("Recording · \(LibraryFormat.duration(context.date.timeIntervalSince(started)))")
                                .font(.ui(11, .semibold))
                                .foregroundStyle(Theme.ink2)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("workspace.recording")
                }
            }
            .padding(.leading, 78)
            .padding(.trailing, 14)
        }
        .frame(height: 40)
        .background(Theme.tree)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct TitlebarRecordingPulse: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

private struct NoteColumn: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            if let record = app.selectedSession {
                SessionWorkspaceView(record: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspace.library")
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
