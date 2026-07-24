import SwiftUI

/// Which built-in section of the tree is driving the note list.
enum LibrarySection: Equatable { case all, inbox, journal }

@MainActor
extension AppModel {
    /// Tree → select a built-in section (Inbox / All notes / Journal).
    func selectLibrarySection(_ section: LibrarySection) {
        librarySection = section
        libraryProjectFilterID = nil
        activeProjectID = nil
        libraryLabelFilter = nil
        historyTypeFilter = section == .journal ? .journal : .all
    }

    /// Tree → select a project folder.
    func selectLibraryProject(_ id: UUID) {
        librarySection = .all
        libraryProjectFilterID = id
        activeProjectID = id
        libraryLabelFilter = nil
        historyTypeFilter = .all
    }

    /// Notes shown in the middle column for the current tree selection.
    var libraryNotes: [SessionRecord] {
        var base = filteredHistory
        if librarySection == .inbox { base = base.filter { $0.projectID == nil } }
        return base
    }

    /// Stable, distinct accent for a project dot (violet / mint / amber / cyan cycle).
    func libraryColor(for projectID: UUID?) -> Color {
        guard let projectID,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return Theme.faint }
        let palette: [Color] = [Theme.violet, Theme.mint, Theme.amber, Theme.cyan]
        return palette[index % palette.count]
    }
}

// MARK: - Column 1 · Project tree

struct ProjectTreeColumn: View {
    @Environment(AppModel.self) private var app
    @State private var showCreateProject = false
    @State private var newProjectName = ""

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader
            searchField
            if !app.historySearch.isEmpty { memoryAsk }

            sectionRows
                .padding(.top, 11)

            HStack {
                Text("PROJECTS").font(.ui(10, .semibold)).tracking(1.3).foregroundStyle(Theme.faint)
                Spacer()
                Button { showCreateProject = true } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.violet).help("Novo projeto")
                .popover(isPresented: $showCreateProject) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Novo projeto").font(.headline)
                        TextField("Nome do projeto", text: $newProjectName)
                            .textFieldStyle(.roundedBorder).onSubmit(createProject)
                        Button("Criar", action: createProject).buttonStyle(.borderedProminent)
                    }
                    .padding(14).frame(width: 260)
                }
            }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 6)

            ScrollView { projectRows }

            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 9).padding(.vertical, 12)
        .frame(width: 224)
        .background(Theme.tree)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 9) {
            Text("C")
                .font(.ui(12, .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.violet, in: RoundedRectangle(cornerRadius: 6))
            Text("CueMe").font(.ui(13.5, .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
    }

    private var searchField: some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.faint)
            TextField("Search", text: $app.historySearch)
                .textFieldStyle(.plain).font(.ui(12.5))
                .accessibilityIdentifier("memory.search")
            if app.historySearch.isEmpty {
                Text("⌘K").font(.ui(9.5)).foregroundStyle(Theme.faint)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
            } else {
                Button { app.historySearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
        .padding(.top, 9)
    }

    private var memoryAsk: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { app.askGlobalMemory() } label: {
                Label(app.globalMemoryAnswering ? "Consultando…" : "Perguntar à memória", systemImage: "sparkles")
                    .font(.ui(10.5, .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small).tint(Theme.violet)
            .accessibilityIdentifier("memory.ask")
            .disabled(app.globalMemoryAnswering)
            if let answer = app.globalMemoryAnswer {
                ScrollView {
                    Text(.init(answer)).font(.ui(10.5)).textSelection(.enabled)
                        .accessibilityIdentifier("memory.answer").accessibilityValue(answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140).padding(8)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(.top, 8)
    }

    private var sectionRows: some View {
        VStack(spacing: 1) {
            sectionRow("Inbox", icon: "tray", section: .inbox)
            sectionRow("All notes", icon: "line.3.horizontal", section: .all, count: app.history.count)
            sectionRow("Journal", icon: "sparkles", section: .journal)
        }
    }

    private func sectionRow(_ title: String, icon: String, section: LibrarySection, count: Int? = nil) -> some View {
        let selected = app.libraryProjectFilterID == nil && app.librarySection == section
        return Button { app.selectLibrarySection(section) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 15)
                Text(title).font(.ui(13))
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.ui(10.5)).foregroundStyle(Theme.faint) }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.canvas : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var projectRows: some View {
        VStack(spacing: 1) {
            ForEach(app.projects.filter { !$0.archived }) { project in
                let selected = app.libraryProjectFilterID == project.id
                Button { app.selectLibraryProject(project.id) } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(app.libraryColor(for: project.id))
                            .frame(width: 9, height: 9)
                        Text(project.name).font(.ui(13, selected ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? Theme.canvas : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("project.\(project.id.uuidString)")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Button { _ = app.createMemoryNote(kind: .note) } label: {
                Text("＋ New note").font(.ui(12.5, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.violet, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).accessibilityIdentifier("sidebar.new-note")

            Button(action: app.showLiveSession) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8)
                    .padding(9)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
            .buttonStyle(.plain).help("Nova gravação")

            Button { app.chooseAudioFiles() } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                    .padding(9)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
            .buttonStyle(.plain)
            .help("Importar áudio")
            .disabled(app.isSessionBusy || app.audioImportStatus?.isActive == true)
        }
        .overlay(alignment: .top) {
            if let status = app.audioImportStatus {
                ImportStatusRow(status: status).offset(y: -58)
            }
        }
    }

    private func createProject() {
        guard let id = app.createProject(named: newProjectName) else { return }
        app.selectLibraryProject(id)
        newProjectName = ""
        showCreateProject = false
    }
}

// MARK: - Column 2 · Note list

struct NoteListColumn: View {
    @Environment(AppModel.self) private var app
    @State private var compact = false

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .frame(width: 298)
        .background(Theme.list)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(app.libraryColor(for: app.libraryProjectFilterID))
                    .frame(width: 11, height: 11)
                Text(headerTitle).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                densityButton("list.bullet", active: !compact) { compact = false }
                densityButton("list.dash", active: compact) { compact = true }
                Button { _ = app.createMemoryNote(kind: .note) } label: {
                    Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                tab("All", filter: .all)
                tab("Meetings", filter: .meeting)
                tab("Notes", filter: .note)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func densityButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.ink2)
                .frame(width: 22, height: 22)
                .background(active ? Theme.soft : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func tab(_ title: String, filter: HistoryTypeFilter) -> some View {
        let active = app.historyTypeFilter == filter
        return Button { app.historyTypeFilter = filter } label: {
            Text(title).font(.ui(11, .semibold))
                .foregroundStyle(active ? Theme.ink : Theme.faint)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? Theme.violet : .clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if app.isRunning { LiveNoteRow() }
                ForEach(app.libraryNotes) { record in
                    NoteRow(record: record, snippet: app.historySnippet(for: record.id), compact: compact)
                }
            }
            .padding(7)
        }
    }

    private var headerTitle: String {
        if let id = app.libraryProjectFilterID {
            return app.projects.first { $0.id == id }?.name ?? "Project"
        }
        switch app.librarySection {
        case .all: return "All notes"
        case .inbox: return "Inbox"
        case .journal: return "Journal"
        }
    }
}

// MARK: - Rows

private struct NoteRow: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    let snippet: String?
    let compact: Bool

    var body: some View {
        let selected = app.selectedSessionID == record.id
        Button { app.selectSession(record.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: record.noteKind.icon).font(.system(size: 10))
                        .foregroundStyle(Theme.ink2).frame(width: 15)
                    Text(LibraryFormat.kindTag(record)).font(.ui(9.5, .semibold)).tracking(1)
                        .foregroundStyle(Theme.faint)
                    Spacer(minLength: 0)
                    Text(LibraryFormat.rightMeta(record)).font(.ui(10)).foregroundStyle(Theme.faint)
                }
                Text(record.title).font(.ui(14.5, .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !compact {
                    if let line = LibraryFormat.preview(record, snippet: snippet) {
                        Text(line).font(.ui(12)).foregroundStyle(Theme.ink2).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if !record.labels.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(record.labels.prefix(3), id: \.self) { label in
                                Text(label).font(.ui(10)).foregroundStyle(Theme.ink2)
                                    .padding(.horizontal, 7).padding(.vertical, 1)
                                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, compact ? 8 : 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.violet)
                        .frame(width: 3).padding(.vertical, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.\(record.id.uuidString)")
        .contextMenu {
            Button("Apagar", systemImage: "trash", role: .destructive) { app.deleteHistory(record.id) }
        }
    }
}

/// Synthetic top row shown while a live session is capturing.
private struct LiveNoteRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let selected = app.selectedSessionID == nil
        Button(action: app.showLiveSession) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                        .modifier(LivePulse())
                    Text("MEETING · LIVE").font(.ui(9.5, .semibold)).tracking(1)
                        .foregroundStyle(Theme.amberText)
                    Spacer(minLength: 0)
                    if let started = app.sessionStartTime { ElapsedClock(from: started) }
                }
                Text(app.brief.goal.isEmpty ? "Sessão ao vivo" : app.brief.goal)
                    .font(.ui(14.5, .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.violet).frame(width: 3).padding(.vertical, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.live")
    }
}

/// mm:ss clock that ticks while live.
struct ElapsedClock: View {
    let from: Date
    var body: some View {
        TimelineView(.periodic(from: from, by: 1)) { context in
            Text(LibraryFormat.duration(context.date.timeIntervalSince(from)))
                .font(.ui(10, .semibold)).foregroundStyle(Theme.amberText).monospacedDigit()
        }
    }
}

private struct LivePulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Formatting

enum LibraryFormat {
    static func kindTag(_ r: SessionRecord) -> String {
        switch r.noteKind {
        case .note: return "NOTE"
        case .journal: return "JOURNAL"
        default: return (r.containsRecording || r.origin == .live) ? "MEETING" : "NOTE"
        }
    }

    static func rightMeta(_ r: SessionRecord) -> String {
        var parts = [relative(r.startedAt)]
        if r.containsRecording, r.audioDuration > 0 { parts.append(duration(r.audioDuration)) }
        return parts.joined(separator: " · ")
    }

    static func preview(_ r: SessionRecord, snippet: String?) -> String? {
        if let snippet, !snippet.isEmpty { return snippet }
        let overview = r.minutes.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty { return overview }
        if let bullet = r.summaryBullets.first, !bullet.isEmpty { return bullet }
        let body = r.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : String(body.prefix(120))
    }

    static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Import status toast

private struct ImportStatusRow: View {
    @Environment(AppModel.self) private var app
    let status: AudioImportStatus

    var body: some View {
        HStack(spacing: 7) {
            if status.isActive {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: status.phase == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(status.phase == .completed ? Theme.mint : Theme.rose)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).font(.ui(9.5, .semibold)).lineLimit(1)
                Text(status.detail).font(.ui(8.5)).foregroundStyle(Theme.ink2).lineLimit(2)
            }
            Spacer(minLength: 0)
            if status.phase == .failed, let sessionID = status.sessionID {
                Button { Task { await app.retryImportedProcessing(sessionID: sessionID) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Tentar novamente")
            } else if !status.isActive {
                Button(action: app.dismissAudioImportStatus) { Image(systemName: "xmark") }
            }
        }
        .buttonStyle(.plain)
        .padding(8).frame(width: 206)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }
}
