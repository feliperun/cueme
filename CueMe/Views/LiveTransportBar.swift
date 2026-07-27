import SwiftUI

struct LiveTransportBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 15, weight: .semibold))
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
            Spacer(minLength: 6)
            if !app.brief.mode.isPassive, app.pendingCoachCount > 0 {
                Label("\(app.pendingCoachCount)", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(Theme.violet.opacity(0.12), in: Capsule())
                    .help("Novas dicas no histórico")
            }
            LiveParticipantButton()
            LiveNoteButton()
            LiveDetailsButton()
            if app.brief.mode.isPassive {
                Button(action: app.stop) {
                    Label("Stop & save", systemImage: "stop.fill")
                        .font(.ui(11, .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
                .accessibilityIdentifier("live.stop")
                .disabled(app.sessionState == .stopping)
            }
        }
        .padding(10)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

struct LiveParticipantButton: View {
    @Environment(AppModel.self) private var app
    @State private var showingParticipants = false
    @State private var selfName = ""
    @State private var otherName = ""

    var body: some View {
        Button {
            selfName = app.participantNames[.self] ?? "Você"
            otherName = app.participantNames[.other] ?? "Interlocutor"
            showingParticipants.toggle()
        } label: {
            Image(systemName: "person.2")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("live.participants")
        .help("Nomear participantes")
        .popover(isPresented: $showingParticipants) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Participantes", systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .bold))
                TextField("Você", text: $selfName)
                    .accessibilityIdentifier("live.participant.self")
                TextField("Interlocutor", text: $otherName)
                    .accessibilityIdentifier("live.participant.other")
                Button("Salvar") {
                    app.setParticipantName(selfName, for: .self)
                    app.setParticipantName(otherName, for: .other)
                    showingParticipants = false
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("live.participants.save")
            }
            .textFieldStyle(.roundedBorder)
            .padding(14)
            .frame(width: 240)
        }
    }
}
