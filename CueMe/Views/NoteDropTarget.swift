import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A dragged row carries just the note's id. Loading it is asynchronous, so
/// the handler hops back to the main actor before touching the model.
enum NoteDragPayload {
    static func provider(for id: UUID) -> NSItemProvider {
        NSItemProvider(object: id.uuidString as NSString)
    }

    static func load(from providers: [NSItemProvider], perform: @escaping @MainActor (UUID) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let raw = value as? String, let id = UUID(uuidString: raw) else { return }
            Task { @MainActor in perform(id) }
        }
        return true
    }
}

/// The accessibility identifiers the tree exposes. They are the contract the
/// E2E scenario drives the tree through, so they are built in one place rather
/// than interpolated at each call site.
enum NoteTreeIdentifier {
    static func container(_ id: UUID) -> String { "tree.container.\(id.uuidString)" }
    static func child(_ id: UUID) -> String { "tree.note.\(id.uuidString)" }
    static func disclosure(_ id: UUID) -> String { "tree.note.disclosure.\(id.uuidString)" }
    static let rootDropZone = "tree.root.dropzone"
    static let live = "tree.live"
}

/// Where a dragged note would land. Kept apart from the drop modifier so the
/// rules — can this be dropped here, and what happens to the subtree — are
/// decided in one testable place instead of inside a gesture.
enum NoteDropTarget {
    enum Destination: Equatable {
        case under(UUID)
        case root
    }

    /// The destination a drop resolves to, or `nil` when the drop is refused.
    ///
    /// Refused means one of: dropping a note on itself, into its own subtree
    /// (which would detach it from the corpus), or where it already is.
    /// `CorpusStore.canPlace` owns the subtree rule — the tree does not get its
    /// own copy of it.
    static func resolve(
        dragging draggedID: UUID,
        onto targetID: UUID?,
        in history: [MemoryNote]
    ) -> Destination? {
        guard let dragged = history.first(where: { $0.id == draggedID }) else { return nil }
        guard let targetID else {
            return (dragged.relativeFolderPath ?? "").isEmpty ? nil : .root
        }
        guard targetID != draggedID, let target = history.first(where: { $0.id == targetID }) else { return nil }

        let destination = NoteTreeProjection.subtreePath(of: target)
        guard CorpusStore.canPlace(dragged, in: destination) else { return nil }
        guard (dragged.relativeFolderPath ?? "") != destination else { return nil }
        return .under(targetID)
    }

    static func accepts(dragging draggedID: UUID, onto targetID: UUID?, in history: [MemoryNote]) -> Bool {
        resolve(dragging: draggedID, onto: targetID, in: history) != nil
    }
}

/// Applying a resolved drop to the in-memory tree.
enum NoteTreeMove {
    struct Outcome: Equatable {
        let history: [MemoryNote]
        /// Non-nil when the move was refused or failed on disk. The tree is
        /// left exactly as it was — it must never show a shape the filesystem
        /// does not have.
        let warning: String?
    }

    /// Moves `draggedID` under `targetID` (or to the root when nil).
    ///
    /// `move` is a parameter so the disk failure can be exercised; in the app
    /// it is `CorpusStore.move`. On success the dragged note takes the address
    /// the store reports, and its descendants are re-parented onto the new
    /// prefix — the folder moved as a unit on disk, so the projection has to
    /// follow as a unit too.
    static func apply(
        dragging draggedID: UUID,
        onto targetID: UUID?,
        in history: [MemoryNote],
        move: (MemoryNote, MemoryNote?) -> CorpusStore.RelocationOutcome?
    ) -> Outcome {
        guard let destination = NoteDropTarget.resolve(dragging: draggedID, onto: targetID, in: history),
              let dragged = history.first(where: { $0.id == draggedID }) else {
            return Outcome(history: history, warning: nil)
        }
        let parent = targetID.flatMap { id in history.first { $0.id == id } }
        guard case .under = destination else { return performed(dragged, under: nil, in: history, move: move) }
        return performed(dragged, under: parent, in: history, move: move)
    }

    private static func performed(
        _ dragged: MemoryNote,
        under parent: MemoryNote?,
        in history: [MemoryNote],
        move: (MemoryNote, MemoryNote?) -> CorpusStore.RelocationOutcome?
    ) -> Outcome {
        let oldPrefix = NoteTreeProjection.subtreePath(of: dragged)
        guard let outcome = move(dragged, parent) else {
            return Outcome(history: history, warning: "Não foi possível mover “\(dragged.title)”.")
        }
        let newPrefix = NoteTreeProjection.subtreePath(of: outcome.note)

        let updated = history.map { note -> MemoryNote in
            if note.id == dragged.id { return outcome.note }
            let path = note.relativeFolderPath ?? ""
            guard path == oldPrefix || path.hasPrefix(oldPrefix + "/") else { return note }
            var descendant = note
            descendant.relativeFolderPath = newPrefix + path.dropFirst(oldPrefix.count)
            return descendant
        }
        return Outcome(history: updated, warning: nil)
    }
}
