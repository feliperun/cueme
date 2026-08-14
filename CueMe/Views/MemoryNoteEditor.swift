import SwiftUI

/// The `Document` surface of a note: masthead, blocks and — while the note is
/// still empty — the affordances that turn it into a meeting.
struct MemoryNoteEditor: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote
    let editor: NoteEditorState

    @State private var document: MarkdownBlockDocument
    @State private var rawDraft: String

    init(record: MemoryNote, editor: NoteEditorState) {
        self.record = record
        self.editor = editor
        _document = State(initialValue: MarkdownBlockDocument(markdown: record.markdownBody))
        _rawDraft = State(initialValue: record.markdownBody)
    }

    var body: some View {
        @Bindable var editor = editor

        Group {
            if editor.sourceMode {
                sourceEditor
            } else {
                documentScroll
            }
        }
        .background(Theme.paper)
        .task(id: document.markdown) {
            guard !editor.sourceMode else { return }
            await persist(document.markdown)
        }
        .task(id: rawDraft) {
            guard editor.sourceMode else { return }
            await persist(rawDraft)
        }
        .onChange(of: editor.sourceMode) { _, isSource in syncSourceMode(isSource) }
        .onChange(of: record.markdownBody) { _, value in
            let current = editor.sourceMode ? rawDraft : document.markdown
            guard value != current else { return }
            rawDraft = value
            document = MarkdownBlockDocument(markdown: value)
        }
        .onDisappear {
            let latest = editor.sourceMode ? rawDraft : document.markdown
            if latest != record.markdownBody { app.updateMarkdownBody(record.id, body: latest) }
        }
    }

    /// The note as one scrolling page: masthead, blocks, then — while the note
    /// is still empty — the affordances that turn it into a meeting.
    private var documentScroll: some View {
        @Bindable var editor = editor

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NoteMasthead(record: record).padding(.bottom, 26)
                MarkdownBlockEditor(
                    document: $document,
                    focusedBlockID: $editor.focusedBlockID,
                    formatRequest: editor.formatRequest,
                    insertBlockRequest: editor.insertBlockRequest
                )
                // Empty-note affordances sit *below* the blocks so the first
                // block stays at the top and immediately focusable.
                if isBlank { BlankNoteState(record: record, editor: self.editor) }
            }
            .frame(maxWidth: NoteDocumentBand.readingWidth, alignment: .leading)
            .padding(.horizontal, NoteDocumentBand.gutter)
            .padding(.top, NoteDocumentBand.topPadding)
            .padding(.bottom, NoteDocumentBand.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.paper)
        .accessibilityIdentifier("note.editor.blocks")
    }

    /// A brand-new written note with nothing typed yet.
    private var isBlank: Bool {
        record.origin == .written
            && record.transcript.isEmpty
            && document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rawDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceEditor: some View {
        TextEditor(text: $rawDraft)
            .font(.system(size: 14.5, weight: .regular, design: .monospaced))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: NoteDocumentBand.readingWidth)
            .padding(.horizontal, NoteDocumentBand.gutter)
            .padding(.vertical, NoteDocumentBand.topPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .accessibilityIdentifier("note.editor.raw")
    }

    /// Keeps the raw draft and the block projection in step when the header
    /// flips the shared `sourceMode`.
    private func syncSourceMode(_ isSource: Bool) {
        if isSource {
            rawDraft = document.markdown
        } else {
            document = MarkdownBlockDocument(markdown: rawDraft)
        }
        editor.focusedBlockID = nil
    }

    private func persist(_ value: String) async {
        guard value != record.markdownBody else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        app.updateMarkdownBody(record.id, body: value)
    }
}

/// Empty-note surface: record / import / playbook affordances so a fresh note
/// is never a dead end. Absorbs the launch affordances into the note itself.
private struct BlankNoteState: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote
    let editor: NoteEditorState
    @State private var playbook: Mode = .meeting

    private let playbooks: [(String, Mode)] = [
        ("Sales", .sales),
        ("Interview", .interview),
        ("Difficult conversation", .difficult),
        ("Open meeting", .meeting),
        ("Recording only — no coach", .recording),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Comece a escrever — ou traga a reunião para esta nota:")
                .font(.read(17)).italic().foregroundStyle(Theme.faint)

            HStack(alignment: .top, spacing: 12) {
                recordCard.frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    smallCard(title: "⤓ Importar áudio", detail: "Voice Memos, arquivo ou arraste — transcrito aqui") {
                        app.chooseAudioFiles()
                    }
                    .disabled(app.isSessionBusy || app.audioImportStatus?.isActive == true)
                    smallCard(title: "/ Inserir bloco", detail: "Títulos, listas, blocos de reunião") {
                        editor.requestInsertBlock()
                    }
                    .accessibilityIdentifier("note.blank.insert-block")
                }
                .frame(maxWidth: 240)
            }

            playbookSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordCard: some View {
        Button(action: startRecording) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(Theme.amber).frame(width: 30, height: 30)
                        Circle().fill(.white).frame(width: 10, height: 10)
                    }
                    Text("Gravar esta reunião").font(.ui(15, .bold)).foregroundStyle(Theme.amberText)
                    Spacer(minLength: 6)
                    Text("⌘R").font(.ui(10)).foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("Mic + áudio do sistema, os dois lados transcritos. Gravação, transcrição e ata viram blocos desta nota.")
                    .font(.ui(12.5)).foregroundStyle(Theme.amberText).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amberSoft, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.amber.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityIdentifier("note.blank.record")
    }

    private func smallCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.ui(11.5)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
    }

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SE VOCÊ GRAVAR — PLAYBOOK DO COACH")
                .font(.ui(10, .semibold)).tracking(1.2).foregroundStyle(Theme.faint)
            FlowPills(items: playbooks.map(\.0), selectedIndex: playbooks.firstIndex { $0.1 == playbook }) { idx in
                playbook = playbooks[idx].1
            }
            Text("Anexe um briefing ou docs de contexto no preflight · STT on-device por padrão")
                .font(.ui(11.5)).foregroundStyle(Theme.faint)
        }
    }

    private func startRecording() {
        app.brief.mode = playbook
        app.showLiveSession()
        app.start()
    }
}

/// Simple wrapping pill row with single selection.
private struct FlowPills: View {
    let items: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                    let selected = index == selectedIndex
                    Button { onSelect(index) } label: {
                        HStack(spacing: 5) {
                            Text(title).font(.ui(12, selected ? .semibold : .regular)).fixedSize()
                            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        }
                        .foregroundStyle(selected ? Theme.violetDeep : Theme.ink2)
                        .padding(.horizontal, 13).padding(.vertical, 5)
                        .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.violet.opacity(0.35) : Theme.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
