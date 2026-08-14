import SwiftUI

/// The thin "recording" band shown above the workspace while a session is
/// live. Split out of `SessionWorkspaceView`, which is the workspace itself.
struct LiveStrip: View {
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
