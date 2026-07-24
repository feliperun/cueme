import SwiftUI

/// Live capture as a note state: coach is the hero, transcript is peripheral.
/// Brief bar (independent STT / Coach / Minutes pickers) · coach hero + live
/// minutes · peripheral transcript rail · dark transport with Stop primary.
struct LiveNoteView: View {
    @Environment(AppModel.self) private var app
    @State private var showMemory = false

    var body: some View {
        VStack(spacing: 0) {
            briefBar
            Rectangle().fill(Theme.line).frame(height: 1)

            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    mainColumn
                    Rectangle().fill(Theme.line).frame(width: 1)
                    transcriptRail
                }
                if showMemory {
                    LiveMemoryDrawer(isOpen: $showMemory)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.snappy(duration: 0.22), value: showMemory)

            transport
        }
        .background(Theme.paper)
    }

    // MARK: Brief bar

    private var briefBar: some View {
        @Bindable var app = app
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                liveChip
                modeMenu
                Text("\(app.brief.conversationLang) → \(app.brief.nativeLang)")
                    .font(.ui(11)).foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))

                Rectangle().fill(Theme.line).frame(width: 1, height: 16)

                pickerChip(prefix: "STT", value: app.sttSource.shortLabel, tint: Theme.faint) {
                    ForEach(SttSource.allCases) { source in
                        Button(source.label) { app.sttSource = source }
                    }
                }
                pickerChip(prefix: "Coach", value: app.coachModel.shortLabel, tint: Theme.mintDeep) {
                    ForEach(CoachModel.allCases) { model in
                        Button(model.label) { app.coachModel = model }
                    }
                    Divider()
                    Text("Troca no próximo card · failover: DeepSeek")
                }
                pickerChip(prefix: "Minutes", value: app.summaryModel.shortLabel, tint: Theme.faint) {
                    ForEach(CoachModel.allCases) { model in
                        Button(model.label) { app.summaryModel = model }
                    }
                }

                Spacer(minLength: 8)

                Button { showMemory.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                        Text("Past notes").font(.ui(11))
                        Text("⌘K").font(.ui(9)).foregroundStyle(Theme.faint)
                            .padding(.horizontal, 3).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.line))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityIdentifier("live.past-notes")

                LiveHealthStrip()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private var liveChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill").font(.system(size: 6))
                .symbolEffect(.pulse, options: .repeating, isActive: true)
            Text("LIVE").font(.ui(10, .semibold)).tracking(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Theme.amber, in: RoundedRectangle(cornerRadius: 5))
    }

    private var modeMenu: some View {
        @Bindable var app = app
        return Menu {
            ForEach(Mode.allCases) { mode in
                Button(mode.label) { app.brief.mode = mode }
            }
        } label: {
            Text("\(app.brief.mode.label) ▾").font(.ui(11)).foregroundStyle(Theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func pickerChip<Content: View>(
        prefix: String, value: String, tint: Color, @ViewBuilder menu: () -> Content
    ) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 5) {
                Text(prefix).font(.ui(11, .semibold)).foregroundStyle(tint)
                Text("\(value) ▾").font(.ui(11)).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    // MARK: Main column (coach hero + live minutes)

    private var mainColumn: some View {
        VStack(spacing: 0) {
            CoachingPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if !app.minutes.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveMinutes
            }
        }
    }

    private var liveMinutes: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("MINUTES").font(.ui(10, .semibold)).tracking(1).foregroundStyle(Theme.ink2)
                if app.isRunning {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.mint)
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                        Text("updating").font(.ui(10, .semibold)).foregroundStyle(Theme.mintDeep)
                    }
                }
                Spacer()
            }
            Text(app.minutes.overview)
                .font(.read(15)).foregroundStyle(Theme.ink2).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }

    // MARK: Transcript rail (peripheral)

    private var transcriptRail: some View {
        let lines = app.transcript.filter(\.isFinal).suffix(4)
        return ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    Text("TRANSCRIPT · LAST TURNS").font(.ui(10, .semibold)).tracking(1)
                        .foregroundStyle(Theme.faint)
                    Spacer()
                }
                if lines.isEmpty {
                    Text("Ouvindo…").font(.read(13.5)).foregroundStyle(Theme.faint)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    railTurn(line, faded: index == 0 && lines.count > 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(width: 308)
        .background(Theme.canvas)
    }

    private func railTurn(_ line: TranscriptLine, faded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(app.participantNames[line.speaker] ?? line.speaker.label)")
                .font(.ui(10, .semibold))
                .foregroundStyle(line.speaker == .self ? Theme.violet : Theme.amberText)
            Text(line.text).font(.read(13.5)).foregroundStyle(Theme.ink).lineSpacing(2)
            if app.brief.isForeign, let translation = line.translation, !translation.isEmpty {
                Text("↳ \(translation)").font(.read(11.5)).italic().foregroundStyle(Theme.faint)
            }
        }
        .opacity(faded ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Dark transport

    private var transport: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(Theme.amber)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                if let start = app.sessionStartTime {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(LibraryFormat.duration(context.date.timeIntervalSince(start)))
                            .font(.ui(15, .semibold)).monospacedDigit()
                    }
                }
            }
            .foregroundStyle(Color(hex: 0xE9E4D6))

            Spacer()

            LiveNoteButton()

            Menu {
                Button(app.silenceMode ? "Reativar coach" : "Silenciar coach", action: app.toggleSilence)
            } label: {
                Text("⋯").font(.ui(13, .semibold)).foregroundStyle(Color(hex: 0xE9E4D6))
                    .frame(width: 34, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.28)))
            }
            .menuStyle(.borderlessButton).fixedSize()

            Button(action: app.stop) {
                Label("Stop & save", systemImage: "stop.fill")
                    .font(.ui(12, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.violet, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.stop")
            .disabled(app.sessionState == .stopping)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Color(hex: 0x2C2A24))
    }
}

// MARK: - Model short labels for the brief bar

private extension SttSource {
    var shortLabel: String { self == .native ? "On-device" : "Deepgram" }
}

private extension CoachModel {
    var shortLabel: String {
        switch self {
        case .sonnet: return "Claude Sonnet"
        case .opus: return "Claude Opus"
        case .deepseekPro: return "DeepSeek Pro"
        case .deepseekFlash: return "DeepSeek Flash"
        }
    }
}
