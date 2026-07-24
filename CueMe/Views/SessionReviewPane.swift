import SwiftUI

struct SessionReviewPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    let player: MeetingPlayer

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                toolbar
                CoachCuesBlock(record: record)
                EditableOverview(record: record)
                topics
                EditableTakeawaysSection(record: record, player: player)
                ReviewItemsSection(record: record, player: player, openQuestion: false)
                ReviewItemsSection(record: record, player: player, openQuestion: true)
                EditableFollowUp(record: record)
                generationActions
                SessionHealthDisclosure(record: record)
                if let error = app.postProcessingError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.rose)
                }
            }
            .padding(14)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("REVISÃO", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.mint)
            Spacer()
            Picker("Modelo", selection: Binding(
                get: { app.summaryModel }, set: { app.summaryModel = $0 }
            )) {
                ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
            Button {
                Task { await app.generateReview(for: record.id) }
            } label: {
                Image(systemName: app.postProcessingSessionID == record.id ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(app.postProcessingSessionID != nil)
            .help("Regenerar revisão")
        }
    }

    private var topics: some View {
        ReviewSection(title: "ASSUNTOS", icon: "square.stack.3d.up") {
            if record.minutes.topics.isEmpty {
                ReviewEmptyRow(text: "Nenhum assunto identificado")
            }
            ForEach(record.minutes.topics) { topic in
                EditableMeetingTopic(sessionID: record.id, topic: topic)
            }
        }
    }

    private var generationActions: some View {
        ReviewSection(title: "GERAR", icon: "wand.and.stars") {
            HStack(spacing: 8) {
                ForEach(FollowUpFormat.allCases) { format in
                    Button {
                        Task { await app.generateFollowUp(for: record.id, format: format) }
                    } label: {
                        Label(format.label, systemImage: format.icon)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(app.postProcessingSessionID != nil)
                }
            }
        }
    }
}

struct ReviewSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Session health behind a collapsed row. Coach P50/P95 is dev jargon inside a
/// note — expanded by default only when the session had recoveries or errors.
private struct SessionHealthDisclosure: View {
    let record: SessionRecord
    @State private var expanded: Bool

    private let integrity: SessionIntegrityReport
    private let performance: SessionPerformanceReport

    init(record: SessionRecord) {
        self.record = record
        let integrity = SessionIntegrityReport(record: record)
        let performance = SessionPerformanceReport(diagnostics: record.diagnostics)
        self.integrity = integrity
        self.performance = performance
        _expanded = State(initialValue: performance.recoveries > 0 || performance.errors > 0)
    }

    private var summary: String {
        let recoveries = "\(performance.recoveries) recuperaç\(performance.recoveries == 1 ? "ão" : "ões")"
        let errors = performance.errors == 0 ? "sem erros" : "\(performance.errors) erros"
        return "\(recoveries), \(errors)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Circle().fill(integrity.isHealthy ? Theme.mint : Theme.amber).frame(width: 7, height: 7)
                    Text("Session health").font(.ui(12, .semibold)).foregroundStyle(Theme.ink2)
                    Text(summary).font(.ui(11.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note.session-health")

            if expanded {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
                LazyVGrid(columns: columns, spacing: 8) {
                    metric("COACH P50", latency(performance.firstPhraseP50Ms), tint: Theme.ink)
                    metric("P95", latency(performance.firstPhraseP95Ms), tint: Theme.ink)
                    metric("RECOVERIES", "\(performance.recoveries)", tint: performance.recoveries > 0 ? Theme.amberText : Theme.ink)
                    metric("ERRORS", "\(performance.errors)", tint: performance.errors > 0 ? Theme.rose : Theme.mintDeep)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
            }
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.line))
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.ui(9.5, .semibold)).foregroundStyle(Theme.faint)
            Text(value).font(.ui(18, .semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }

    private func latency(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }
}

struct EditableOverview: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var draft = ""

    var body: some View {
        ReviewSection(title: "RESUMO", icon: "text.alignleft") {
            TextField("Resumo geral", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(10)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                .onSubmit(save)
        }
        .onAppear { draft = record.minutes.overview }
        .onChange(of: record.minutes.overview) { _, value in draft = value }
    }

    private func save() { app.updateMeetingOverview(sessionID: record.id, text: draft) }
}

struct EditableMeetingTopic: View {
    @Environment(AppModel.self) private var app
    let sessionID: UUID
    let topic: MeetingTopic
    @State private var title = ""
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Assunto", text: $title)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.violet)
            TextField("Mini resumo", text: $summary, axis: .vertical)
                .font(.system(size: 12))
        }
        .textFieldStyle(.plain)
        .padding(9)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
        .onSubmit(save)
        .onAppear { title = topic.title; summary = topic.summary }
    }

    private func save() {
        app.updateMeetingTopic(sessionID: sessionID, topicID: topic.id, title: title, summary: summary)
    }
}

struct EditableTakeawayRow: View {
    @Environment(AppModel.self) private var app
    let sessionID: UUID
    let item: SessionTakeaway
    let player: MeetingPlayer?
    @State private var draft = ""

    init(sessionID: UUID, item: SessionTakeaway, player: MeetingPlayer? = nil) {
        self.sessionID = sessionID
        self.item = item
        self.player = player
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { app.toggleTakeaway(sessionID: sessionID, takeawayID: item.id) } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? Theme.mint : .secondary)
            }
            TextField("Ação", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12))
                .strikethrough(item.isDone).onSubmit(save)
            EvidenceButton(ownerID: item.id, evidence: item.evidence, player: player)
            Button(action: save) { Image(systemName: "checkmark") }
            Button(role: .destructive) {
                app.deleteTakeaway(sessionID: sessionID, takeawayID: item.id)
            } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.plain)
        .padding(8).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
        .onAppear { draft = item.text }
        .onChange(of: item.text) { _, value in draft = value }
    }

    private func save() { app.updateTakeaway(sessionID: sessionID, takeawayID: item.id, text: draft) }
}

private struct EditableTakeawaysSection: View {
    let record: SessionRecord
    let player: MeetingPlayer
    var body: some View {
        ReviewSection(title: "AÇÕES", icon: "checklist") {
            if record.takeaways.isEmpty { ReviewEmptyRow(text: "Nenhuma ação pendente") }
            ForEach(record.takeaways) { EditableTakeawayRow(sessionID: record.id, item: $0, player: player) }
        }
    }
}

private struct ReviewItemsSection: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    let player: MeetingPlayer
    let openQuestion: Bool
    @State private var newItem = ""

    private var items: [MeetingReviewItem] {
        openQuestion ? record.review.openQuestions : record.review.decisions
    }

    var body: some View {
        ReviewSection(
            title: openQuestion ? "QUESTÕES EM ABERTO" : "DECISÕES",
            icon: openQuestion ? "questionmark.circle" : "checkmark.diamond"
        ) {
            if items.isEmpty {
                ReviewEmptyRow(text: openQuestion ? "Nenhuma questão aberta" : "Nenhuma decisão confirmada")
            }
            ForEach(items) { item in
                EditableReviewItemRow(
                    sessionID: record.id,
                    item: item,
                    player: player,
                    openQuestion: openQuestion
                )
            }
            HStack {
                TextField(openQuestion ? "Adicionar questão" : "Adicionar decisão", text: $newItem)
                    .textFieldStyle(.plain).font(.system(size: 11.5)).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.brand)
            }
            .padding(8).background(Theme.interactive, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func add() {
        app.addReviewItem(sessionID: record.id, text: newItem, openQuestion: openQuestion)
        newItem = ""
    }
}

private struct EditableReviewItemRow: View {
    @Environment(AppModel.self) private var app
    let sessionID: UUID
    let item: MeetingReviewItem
    let player: MeetingPlayer
    let openQuestion: Bool
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: openQuestion ? "questionmark" : "checkmark")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(openQuestion ? Theme.amber : Theme.mint)
            TextField("Item", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).onSubmit(save)
                .accessibilityIdentifier("review.item.\(item.id.uuidString)")
            EvidenceButton(ownerID: item.id, evidence: item.evidence, player: player)
            Button(action: save) { Image(systemName: "checkmark") }
            Button(role: .destructive) {
                app.deleteReviewItem(sessionID: sessionID, itemID: item.id, openQuestion: openQuestion)
            } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.plain)
        .padding(8).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
        .onAppear { draft = item.text }
        .onChange(of: item.text) { _, value in draft = value }
    }

    private func save() {
        if openQuestion {
            app.updateReviewQuestion(sessionID: sessionID, itemID: item.id, text: draft)
        } else {
            app.updateReviewDecision(sessionID: sessionID, itemID: item.id, text: draft)
        }
    }
}

private struct EvidenceButton: View {
    let ownerID: UUID
    let evidence: [MemoryEvidence]
    let player: MeetingPlayer?

    var body: some View {
        if let first = evidence.first {
            Button {
                player?.seek(to: first.timestamp)
                if player?.isPlaying == false { player?.play() }
            } label: {
                Label("\(evidence.count)", systemImage: "quote.bubble")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("evidence.\(ownerID.uuidString)")
            .accessibilityValue(SessionArchive.clock(first.timestamp))
            .help(first.quote)
        }
    }
}

private struct EditableFollowUp: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var draft = ""

    var body: some View {
        ReviewSection(title: "FOLLOW-UP", icon: "arrowshape.turn.up.right") {
            TextField("Próximo contato recomendado", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12))
                .padding(9).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                .onSubmit(save)
        }
        .onAppear { draft = record.review.followUp }
        .onChange(of: record.review.followUp) { _, value in draft = value }
    }

    private func save() { app.updateReviewFollowUp(sessionID: record.id, text: draft) }
}

struct ReviewEmptyRow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.tertiary).padding(.vertical, 4)
    }
}

/// Post-hoc coach cues as a collapsed log block (mint = coach). Expands to the
/// card carousel; loud hero treatment is reserved for the live layout.
private struct CoachCuesBlock: View {
    let record: SessionRecord
    @State private var expanded = false

    private var cards: [CoachCard] { record.coachCards.filter(\.hasContent) }
    private var usedCount: Int { record.coachFeedback.values.filter { $0 == .helpful }.count }

    var body: some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.mintDeep)
                        Text("COACH CUES").font(.ui(11, .bold)).tracking(1).foregroundStyle(Theme.mintDeep)
                        Text("\(cards.count) durante a conversa · \(usedCount) usadas")
                            .font(.ui(12)).foregroundStyle(Theme.ink2)
                        Spacer(minLength: 8)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.coach-cues")

                if expanded {
                    VStack(spacing: 8) {
                        ForEach(cards) { MemoryCoachCard(card: $0) }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        }
    }
}
