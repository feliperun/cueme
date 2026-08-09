import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The note column's single chrome row: where you are, which projection of the
/// note you are reading, and what you can do with the document as a whole.
///
/// Everything that describes the note itself (title, people, labels, project)
/// lives in `NoteMasthead`, inside the scrolling document.
struct NoteWorkspaceHeaderBar: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote
    @Binding var selection: SessionWorkspaceTab
    let editor: NoteEditorState

    var body: some View {
        HStack(spacing: 10) {
            breadcrumb
            SessionWorkspaceTabs(record: record, selection: $selection)
            Spacer(minLength: 8)
            if selection == .note {
                formatMenu
                sourceToggle
            }
            shareMenu
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 11)
        .background(Theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }

    // MARK: Breadcrumb

    private var breadcrumb: some View {
        Text("\(app.project(for: record)?.name ?? "Sem projeto") /")
            .font(.ui(12))
            .foregroundStyle(Theme.faint)
            .lineLimit(1)
            .accessibilityIdentifier("note.breadcrumb")
    }

    // MARK: Inline formatting

    /// The shortcuts live in the text view; this menu keeps them discoverable
    /// now that the editor no longer carries its own toolbar.
    private var formatMenu: some View {
        Menu {
            formatItem("Negrito", shortcut: "⌘B", style: .bold)
            formatItem("Itálico", shortcut: "⌘I", style: .italic)
            formatItem("Tachado", shortcut: "⌘⇧X", style: .strikethrough)
            formatItem("Código inline", shortcut: "⌘⇧C", style: .code)
        } label: {
            Image(systemName: "textformat").font(.ui(11.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editor.focusedBlockID == nil || editor.sourceMode)
        .help("Formatar a seleção")
        .accessibilityIdentifier("note.editor.format")
    }

    private func formatItem(_ title: String, shortcut: String, style: MarkdownInlineStyle) -> some View {
        Button("\(title)  \(shortcut)") { editor.requestFormat(style) }
            .accessibilityIdentifier("note.editor.format.\(String(describing: style))")
    }

    // MARK: Markdown source

    private var sourceToggle: some View {
        Button { editor.sourceMode.toggle() } label: {
            outlinedLabel(editor.sourceMode ? "Blocos" : "Markdown", active: editor.sourceMode)
        }
        .buttonStyle(.plain)
        .help(editor.sourceMode ? "Voltar ao editor visual" : "Editar o Markdown gerado")
        .accessibilityIdentifier("note.editor.source")
    }

    // MARK: Share

    private var shareMenu: some View {
        Menu {
            Button("Copiar Markdown", systemImage: "doc.on.doc") { copy(record.markdownBody) }
            Button("Copiar JSON", systemImage: "curlybraces") { copy(record.prettyJSON) }
            Button("Exportar JSON…", systemImage: "square.and.arrow.down", action: exportJSON)
            Divider()
            Button("Mostrar arquivos da sessão", systemImage: "folder") {
                app.revealMemoryNote(record.id)
            }
            .accessibilityIdentifier("note.reveal")
        } label: {
            outlinedLabel("Share", active: false)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("note.share")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = record.exportFilename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? record.prettyJSON.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: Styling

    private func outlinedLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.ui(11.5))
            .foregroundStyle(active ? Theme.violetDeep : Theme.ink2)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? Theme.violetSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? .clear : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
