import SwiftUI

// MARK: - Column 2 · Note list

struct NoteListColumn: View {
    @Environment(AppModel.self) private var app
    @State private var compact = false

    var body: some View {
        let projection = app.noteListProjection
        VStack(spacing: 0) {
            header(projection)
            list(projection)
        }
        .frame(width: 298)
        .background(Theme.list)
    }

    private func header(_ projection: NoteListProjection) -> some View {
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
                tab("All \(projection.count(for: .all))", filter: .all, identifier: "all", projection: projection)
                tab("Meetings", filter: .meeting, identifier: "meetings", projection: projection)
                tab("Notes", filter: .note, identifier: "notes", projection: projection)
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

    private func tab(
        _ title: String,
        filter: HistoryTypeFilter,
        identifier: String,
        projection: NoteListProjection
    ) -> some View {
        let active = app.historyTypeFilter == filter
        let count = projection.count(for: filter)
        return Button { app.historyTypeFilter = filter } label: {
            Text(title).font(.ui(11, .semibold))
                .foregroundStyle(active ? Theme.ink : Theme.faint)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? Theme.violet : .clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note-list.tab.\(identifier)")
        .accessibilityValue("\(active ? "selected" : "unselected");\(count)")
    }

    private func list(_ projection: NoteListProjection) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if app.isRunning { LiveNoteRow() }
                ForEach(projection.visibleRecords) { record in
                    NoteRow(record: record, snippet: projection.snippet(for: record.id), compact: compact)
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
        switch r.libraryPresentationKind {
        case .note: return "NOTE"
        case .journal: return "JOURNAL"
        case .meeting: return "MEETING"
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

struct ImportStatusRow: View {
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
                }
                .accessibilityIdentifier("import.retry")
                .help("Tentar novamente")
            } else if !status.isActive {
                Button(action: app.dismissAudioImportStatus) { Image(systemName: "xmark") }
                    .accessibilityIdentifier("import.dismiss")
            }
        }
        .buttonStyle(.plain)
        .padding(8).frame(width: 206)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.status")
        .accessibilityValue(status.phase.rawValue)
    }
}
