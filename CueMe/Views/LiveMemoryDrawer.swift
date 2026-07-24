import SwiftUI

/// ⌘K memory drawer over the live call — search past notes without leaving the
/// call. Results feed **Insert reference** (drops an evidence-linked ref into the
/// note) or **send to coach** (bounded snapshot, explicit invocation only).
struct LiveMemoryDrawer: View {
    @Environment(AppModel.self) private var app
    @Binding var isOpen: Bool
    @State private var query = ""

    private var results: [SessionSearchResult] { app.searchPastNotes(query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            resultsList
            footer
        }
        .frame(width: 428)
        .frame(maxHeight: .infinity)
        .background(Theme.paper)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .shadow(color: .black.opacity(0.18), radius: 24, x: -12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("MEMORY").font(.ui(10, .semibold)).tracking(1.2).foregroundStyle(Theme.violetDeep)
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.amber)
                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                    Text("recording continues").font(.ui(10.5)).foregroundStyle(Theme.amberText)
                }
                Spacer()
                Button { isOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.faint)
                TextField("Buscar notas passadas", text: $query)
                    .textFieldStyle(.plain).font(.ui(13.5))
                    .accessibilityIdentifier("live.memory.search")
            }
            .padding(.horizontal, 11).frame(height: 34)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.violet))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Digite para buscar nas suas notas — a gravação continua.")
                        .font(.ui(12)).foregroundStyle(Theme.faint).padding(.top, 4)
                } else if results.isEmpty {
                    Text("Nenhuma nota relacionada.").font(.ui(12)).foregroundStyle(Theme.faint).padding(.top, 4)
                } else {
                    ForEach(results, id: \.recordID) { result in
                        if let record = app.history.first(where: { $0.id == result.recordID }) {
                            resultCard(record, result: result)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func resultCard(_ record: SessionRecord, result: SessionSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text("\(LibraryFormat.kindTag(record)) · \(LibraryFormat.relative(record.startedAt))")
                    .font(.ui(10, .semibold)).tracking(0.5).foregroundStyle(Theme.faint)
                Spacer()
                Text("relevância \(result.score)").font(.ui(10)).foregroundStyle(Theme.faint)
            }
            Text(record.title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            if let snippet = result.snippet ?? LibraryFormat.preview(record, snippet: nil) {
                Text(snippet).font(.read(13.5)).foregroundStyle(Theme.ink2).lineLimit(3)
            }
            HStack(spacing: 6) {
                Button { app.insertLiveReference(to: record.id) } label: {
                    Text("Inserir referência").font(.ui(10.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Theme.violet, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                Button { app.sendMemoryToCoach(record.id) } label: {
                    Text("⌘↵ enviar ao coach").font(.ui(10.5)).foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.line))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Inserir referência").font(.ui(10.5)).foregroundStyle(Theme.faint)
            Text("⌘↵ enviar ao coach").font(.ui(10.5)).foregroundStyle(Theme.faint)
            Spacer()
            Text("esc fecha").font(.ui(10.5)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }
}
