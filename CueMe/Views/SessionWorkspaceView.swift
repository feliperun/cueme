import SwiftUI

struct SessionWorkspaceView: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var tab: SessionWorkspaceTab = .coach
    @State private var player = MeetingPlayer()
    @State private var envelope: [Float] = []
    @State private var loadingWaveform = false
    @State private var noteText = ""
    @State private var takeawayText = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                WaveformPlayerView(player: player, envelope: envelope, loading: loadingWaveform)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                tabBar
            }
            .background(Theme.sidebar)
            Rectangle().fill(Theme.divider).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
                .transition(.opacity)
        }
        .background(Theme.background)
        .animation(.snappy(duration: 0.18), value: tab)
        .task(id: record.id) { await loadAudio() }
        .onDisappear { player.teardown() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Label(record.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(SessionArchive.clock(record.duration), systemImage: "clock")
                    if record.hasAudio {
                        Label(audioFormatLabel, systemImage: "waveform")
                            .foregroundStyle(Theme.mint)
                    }
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: app.revealArchive) {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButtonStyle())
            .help("Mostrar arquivos da sessão")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SessionWorkspaceTab.allCases) { item in
                SessionTabButton(item: item, count: badge(for: item), selected: tab == item) {
                    withAnimation(.snappy(duration: 0.18)) { tab = item }
                }
            }
        }
        .padding(4)
        .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .coach: coachPane
        case .summary: summaryPane
        case .transcript: transcriptPane
        case .notes: notesPane
        case .takeaways: takeawaysPane
        case .generated: generatedPane
        }
    }

    private var coachPane: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if record.coachCards.isEmpty { emptyState("Sem dicas nesta sessão", icon: "sparkles") }
                ForEach(record.coachCards.reversed()) { card in MemoryCoachCard(card: card) }
            }
            .padding(14)
        }
    }

    private var summaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    generationButton("Atualizar", icon: "arrow.clockwise") {
                        await app.generateSummary(for: record.id)
                    }
                }
                if record.summaryBullets.isEmpty { emptyState("Resumo ainda não gerado", icon: "text.alignleft") }
                ForEach(Array(record.summaryBullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.violet).frame(width: 5, height: 5).padding(.top, 6)
                        Text(bullet).font(.system(size: 13)).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                processingError
            }
            .padding(14)
        }
    }

    private var transcriptPane: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if record.transcript.isEmpty { emptyState("Sem transcrição", icon: "waveform.slash") }
                ForEach(record.transcript) { line in
                    MemoryTranscriptLine(
                        line: line,
                        foreign: record.isForeign,
                        active: line.id == activeLineID,
                        onTap: player.isReady ? { seek(to: line) } : nil
                    )
                }
            }
            .padding(14)
        }
    }

    private var notesPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 7) {
                    if record.notes.isEmpty { emptyState("Anote sem sair da timeline", icon: "note.text") }
                    ForEach(record.notes.sorted { $0.timeOffset < $1.timeOffset }) { note in
                        Button { player.seek(to: note.timeOffset) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Text(SessionArchive.clock(note.timeOffset))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.amber)
                                Text(note.text).font(.system(size: 12.5)).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(9).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            composer(text: $noteText, placeholder: "Nota em \(SessionArchive.clock(player.currentTime))") {
                app.addNote(to: record.id, text: noteText, timeOffset: player.currentTime)
                noteText = ""
            }
        }
    }

    private var takeawaysPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        generationButton("Extrair", icon: "wand.and.stars") {
                            await app.generateTakeaways(for: record.id)
                        }
                    }
                    if record.takeaways.isEmpty { emptyState("Nada pendente ainda", icon: "checklist") }
                    ForEach(record.takeaways) { item in
                        Button { app.toggleTakeaway(sessionID: record.id, takeawayID: item.id) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? Theme.mint : .secondary)
                                Text(item.text)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                Spacer()
                            }
                            .font(.system(size: 12.5)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    processingError
                }
                .padding(14)
            }
            composer(text: $takeawayText, placeholder: "Adicionar pendência") {
                app.addTakeaway(to: record.id, text: takeawayText)
                takeawayText = ""
            }
        }
    }

    private var generatedPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if record.artifacts.isEmpty { emptyState("Pergunte sobre esta reunião", icon: "sparkle.magnifyingglass") }
                    ForEach(record.artifacts.reversed()) { artifact in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artifact.title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.violet)
                            Text(artifact.body).font(.system(size: 12.5)).textSelection(.enabled)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
                    }
                    processingError
                }
                .padding(14)
            }
            @Bindable var app = app
            composer(text: $app.postSessionPrompt, placeholder: "Pergunte ou gere algo…") {
                app.askAboutSession(record.id)
            }
        }
    }

    @ViewBuilder
    private var processingError: some View {
        if let error = app.postProcessingError {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.system(size: 10.5)).foregroundStyle(Theme.rose)
        }
    }

    private func composer(text: Binding<String>, placeholder: String, submit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit(submit)
            Button(action: submit) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.brand)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panel).overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func generationButton(
        _ title: String,
        icon: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Label(app.postProcessingSessionID == record.id ? "Gerando…" : title,
                  systemImage: app.postProcessingSessionID == record.id ? "hourglass" : icon)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(app.postProcessingSessionID != nil)
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.violet.opacity(0.7))
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private var activeLineID: UUID? {
        let target = record.audioTimelineStart.addingTimeInterval(player.currentTime)
        return record.transcript.filter { $0.isFinal && $0.ts <= target }.max { $0.ts < $1.ts }?.id
    }

    private var audioFormatLabel: String {
        let urls = [MeetingRecording.selfURL(for: record), MeetingRecording.otherURL(for: record)]
        let existing = urls.first { FileManager.default.fileExists(atPath: $0.path) }
        switch existing?.pathExtension.lowercased() {
        case "m4a": return "M4A · AAC"
        case "caf": return "CAF · legado"
        default: return "Áudio local"
        }
    }

    private func badge(for tab: SessionWorkspaceTab) -> Int? {
        switch tab {
        case .coach: return record.coachCards.count
        case .summary: return record.summaryBullets.count
        case .transcript: return record.transcript.filter(\.isFinal).count
        case .notes: return record.notes.count
        case .takeaways: return record.takeaways.filter { !$0.isDone }.count
        case .generated: return record.artifacts.count
        }
    }

    private func seek(to line: TranscriptLine) {
        player.seek(to: line.ts.timeIntervalSince(record.audioTimelineStart))
        if !player.isPlaying { player.play() }
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
