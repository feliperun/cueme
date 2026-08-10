import XCTest
@testable import CueMe

/// Dragging a note onto another is the affordance that makes the single-entity
/// model usable. The decision lives in a pure type, so all of it is provable
/// without driving the UI.
final class NoteDropTargetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func note(_ title: String, at path: String) -> MemoryNote {
        var value = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_060),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            displayTitle: title,
            titleSource: .user
        )
        value.archiveFolderName = (path as NSString).lastPathComponent
        value.relativeFolderPath = (path as NSString).deletingLastPathComponent
        return value
    }

    /// Stands in for `CorpusStore.move`: reports the address the store would
    /// have given the note, without touching the disk.
    private func mover(
        failing: Bool = false
    ) -> (MemoryNote, MemoryNote?) -> CorpusStore.RelocationOutcome? {
        { dragged, parent in
            if failing { return nil }
            var moved = dragged
            moved.relativeFolderPath = parent.map(NoteTreeProjection.subtreePath(of:)) ?? ""
            return CorpusStore.RelocationOutcome(
                note: moved,
                fromPath: "/\(NoteTreeProjection.subtreePath(of: dragged)).md",
                toPath: "/\(NoteTreeProjection.subtreePath(of: moved)).md",
                rewrittenDocuments: 0
            )
        }
    }

    // MARK: AC1 — a drop moves the note inside the target

    func testDropOnNoteMovesItUnderTheTarget() {
        let acme = note("Acme", at: "acme")
        let ata = note("Ata", at: "ata")
        let history = [acme, ata]

        XCTAssertEqual(
            NoteDropTarget.resolve(dragging: ata.id, onto: acme.id, in: history),
            .under(acme.id)
        )

        let outcome = NoteTreeMove.apply(dragging: ata.id, onto: acme.id, in: history, move: mover())

        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.history.first { $0.id == ata.id }?.relativeFolderPath, "acme")
        XCTAssertEqual(
            NoteTreeProjection.children(in: outcome.history, of: acme).map(\.title),
            ["Ata"]
        )
    }

    // MARK: AC2 — a parent cannot be dropped into its own descendant

    func testRejectsDropIntoOwnDescendant() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "acme/atas")
        let deep = note("Reunião", at: "acme/atas/reuniao")
        let history = [acme, atas, deep]

        XCTAssertNil(NoteDropTarget.resolve(dragging: acme.id, onto: atas.id, in: history))
        XCTAssertNil(NoteDropTarget.resolve(dragging: acme.id, onto: deep.id, in: history))
        XCTAssertFalse(NoteDropTarget.accepts(dragging: acme.id, onto: deep.id, in: history))
        XCTAssertTrue(NoteDropTarget.accepts(dragging: deep.id, onto: acme.id, in: history))

        let outcome = NoteTreeMove.apply(dragging: acme.id, onto: deep.id, in: history, move: mover())
        XCTAssertEqual(outcome.history.map(\.relativeFolderPath), history.map(\.relativeFolderPath))
    }

    // MARK: AC3 — the whole subtree travels with the note

    func testMovingCarriesTheSubtree() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "atas")
        let child = note("Reunião", at: "atas/reuniao")
        let grandchild = note("Anexo", at: "atas/reuniao/anexo")
        // Its parent directory starts with the same letters as "atas" and is
        // still a different note entirely.
        let bystander = note("Outro", at: "atas-antigas/outro")
        let history = [acme, atas, child, grandchild, bystander]

        let outcome = NoteTreeMove.apply(dragging: atas.id, onto: acme.id, in: history, move: mover())

        XCTAssertEqual(outcome.history.first { $0.id == atas.id }?.relativeFolderPath, "acme")
        XCTAssertEqual(outcome.history.first { $0.id == child.id }?.relativeFolderPath, "acme/atas")
        XCTAssertEqual(
            outcome.history.first { $0.id == grandchild.id }?.relativeFolderPath,
            "acme/atas/reuniao"
        )
        XCTAssertEqual(
            outcome.history.first { $0.id == bystander.id }?.relativeFolderPath,
            "atas-antigas",
            "a sibling whose path merely shares a prefix must not be dragged along"
        )
        XCTAssertEqual(
            Set(NoteTreeProjection.subtree(in: outcome.history, of: acme).map(\.title)),
            ["Acme", "Atas", "Reunião", "Anexo"]
        )
    }

    // MARK: AC4 — a failed move leaves the tree exactly as it was

    func testFailedMoveRevertsTheProjection() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "atas")
        let child = note("Reunião", at: "atas/reuniao")
        let history = [acme, atas, child]

        let outcome = NoteTreeMove.apply(
            dragging: atas.id, onto: acme.id, in: history, move: mover(failing: true)
        )

        XCTAssertEqual(outcome.warning, "Não foi possível mover “Atas”.")
        XCTAssertEqual(outcome.history.map(\.relativeFolderPath), ["", "", "atas"])
        XCTAssertTrue(NoteTreeProjection.children(in: outcome.history, of: acme).isEmpty)
    }

    // MARK: AC5 — dropping on the root unnests

    func testDropOnRootUnnests() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "acme/atas")
        let history = [acme, atas]

        XCTAssertEqual(NoteDropTarget.resolve(dragging: atas.id, onto: nil, in: history), .root)

        let outcome = NoteTreeMove.apply(dragging: atas.id, onto: nil, in: history, move: mover())

        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.history.first { $0.id == atas.id }?.relativeFolderPath, "")
        XCTAssertEqual(
            NoteTreeProjection.rootNotes(in: outcome.history).map(\.title),
            ["Acme", "Atas"]
        )
    }

    // MARK: AC6 — dropping on itself, or where it already is, does nothing

    func testDropOnSelfIsANoOp() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "acme/atas")
        let history = [acme, atas]

        XCTAssertNil(NoteDropTarget.resolve(dragging: acme.id, onto: acme.id, in: history))
        XCTAssertNil(
            NoteDropTarget.resolve(dragging: atas.id, onto: acme.id, in: history),
            "it is already there — a move would rewrite links for nothing"
        )
        XCTAssertNil(
            NoteDropTarget.resolve(dragging: acme.id, onto: nil, in: history),
            "already at the root"
        )

        var moves = 0
        let outcome = NoteTreeMove.apply(dragging: acme.id, onto: acme.id, in: history) { note, parent in
            moves += 1
            return self.mover()(note, parent)
        }

        XCTAssertEqual(moves, 0, "a refused drop must never reach the store")
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.history.map(\.relativeFolderPath), history.map(\.relativeFolderPath))
    }
}
