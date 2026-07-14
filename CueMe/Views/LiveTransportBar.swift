import SwiftUI

struct LiveTransportBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.rose)
                .symbolEffect(.pulse, options: .repeating, isActive: app.isSessionBusy)
            if let start = app.sessionStartTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionArchive.clock(context.date.timeIntervalSince(start)))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                }
            }

            Rectangle().fill(Theme.divider).frame(width: 1, height: 22)

            HStack(spacing: 8) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(Theme.amber)
                TextField("Anotação neste momento…", text: $app.noteDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit(app.addLiveNote)
                Button(action: app.addLiveNote) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.violet)
                .disabled(app.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(10)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
