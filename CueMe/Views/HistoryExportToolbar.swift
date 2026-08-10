import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryExportToolbar: ToolbarContent {
    let record: MemoryNote
    @State private var copied = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(copied ? "Copiado ✓" : "Copiar JSON", systemImage: "doc.on.doc") { copyMarkdown() }
                Button("Exportar JSON…", systemImage: "square.and.arrow.down") { exportMarkdown() }
            } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NoteDocumentWriter.render(record), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = NoteExport.filename(for: record)
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? NoteDocumentWriter.render(record).data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}
