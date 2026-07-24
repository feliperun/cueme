import SwiftUI

struct SessionWorkspaceView: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var tab: SessionWorkspaceTab
    @State private var player = MeetingPlayer()
    @State private var envelope: [Float] = []
    @State private var loadingWaveform = false

    init(record: SessionRecord) {
        self.record = record
        _tab = State(initialValue: record.origin == .written ? .note : .review)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SessionWorkspaceHeader(record: record)
                if isCapturingLive { LiveStrip() }
                if record.containsRecording {
                    WaveformPlayerView(player: player, envelope: envelope, loading: loadingWaveform)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }
                SessionWorkspaceTabs(record: record, selection: $tab)
            }
            .background(Theme.sidebar)
            Rectangle().fill(Theme.divider).frame(height: 1)
            SessionWorkspacePane(record: record, selection: tab, player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
                .transition(.opacity)
            AskCueMeBar(record: record, tab: $tab)
        }
        .background(Theme.paper)
        .animation(.snappy(duration: 0.18), value: tab)
        .task(id: record.id) { await loadAudio() }
        .onDisappear { player.teardown() }
    }

    private var isCapturingLive: Bool {
        app.isRunning && app.currentSessionID == record.id
    }

    private func loadAudio() async {
        player.teardown()
        envelope = []
        let selfURL = MeetingRecording.selfURL(for: record)
        let otherURL = MeetingRecording.otherURL(for: record)
        player.load(selfURL: selfURL, otherURL: otherURL)
        guard player.isReady else { loadingWaveform = false; return }
        loadingWaveform = true
        envelope = await Task.detached(priority: .userInitiated) {
            WaveformGenerator.envelope(selfURL: selfURL, otherURL: otherURL, buckets: 300)
        }.value
        loadingWaveform = false
    }
}

/// Full-width amber bar shown on a note whose session is capturing live.
private struct LiveStrip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(action: app.showLiveSession) {
            HStack(spacing: 9) {
                Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Theme.amber)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                label.foregroundStyle(Theme.amberText)
                Spacer(minLength: 8)
                Text("Open live session →").font(.ui(12, .semibold)).foregroundStyle(Theme.amberText)
            }
            .padding(.horizontal, 26).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amberSoft)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.amber.opacity(0.35)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.live-strip")
    }

    @ViewBuilder private var label: some View {
        if let started = app.sessionStartTime {
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text("Recording · \(LibraryFormat.duration(context.date.timeIntervalSince(started)))")
                    .font(.ui(12, .bold)).monospacedDigit()
                + Text(" — this note is capturing the meeting live").font(.ui(12))
            }
        } else {
            Text("Recording — this note is capturing the meeting live").font(.ui(12))
        }
    }
}
