import Foundation

/// Filename suggested when a note is exported. The export is the note's own
/// document, so the name follows the same slug rule the corpus uses on disk.
enum NoteExport {
    static func filename(for note: MemoryNote) -> String {
        "\(OKFBundle.slug(note.title)).md"
    }
}
