import Foundation
import Observation

/// Editor state the note header row and the block editor both need.
///
/// The single-row header owns controls (Markdown toggle, inline formatting,
/// insert block) that act on an editor rendered further down the workspace, so
/// the state is lifted here instead of being threaded as a bag of bindings.
@Observable
final class NoteEditorState {
    /// Block currently holding the caret — inline formatting targets it.
    var focusedBlockID: UUID?
    /// Latest inline-format request; the text view applies it to its selection.
    var formatRequest: MarkdownBlockFormatRequest?
    /// Raw Markdown instead of the visual blocks.
    var sourceMode = false
    /// Bumped by any surface asking the block editor to open the insert menu.
    private(set) var insertBlockRequest = 0

    func requestFormat(_ style: MarkdownInlineStyle) {
        guard let focusedBlockID else { return }
        formatRequest = .init(blockID: focusedBlockID, style: style)
    }

    func requestInsertBlock() {
        insertBlockRequest += 1
    }

    /// Called when the workspace switches to another note.
    func reset() {
        focusedBlockID = nil
        formatRequest = nil
        sourceMode = false
    }
}
