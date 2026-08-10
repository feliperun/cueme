import XCTest
@testable import CueMe

/// A note is two filesystem objects — `<slug>.md` and, conditionally,
/// `<slug>/`. These cover moving and renaming both together, and what happens
/// to the links that pointed at the old path.
final class CorpusMoveRenameTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeMoveRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func note(_ title: String, titleSource: NoteTitleSource = .user) -> MemoryNote {
        MemoryNote(
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
            titleSource: titleSource,
            modifiedAt: Date(timeIntervalSince1970: 1_060)
        )
    }

    /// T016 AC3: a link is a path, and paths move. The rewrite in T015 is what
    /// keeps the masthead chip resolving after the target changes address.
    @MainActor
    func testALinkKeepsResolvingAfterItsTargetIsMoved() throws {
        var target = note("Marina Souza")
        target = CorpusStore.resolvingLocation(target)
        CorpusStore.save(target)

        var container = note("Pessoas")
        container = CorpusStore.resolvingLocation(container)
        CorpusStore.save(container)

        var source = note("Reunião de kickoff")
        source = CorpusStore.resolvingLocation(source)
        source.links = ["/\(NoteTreeProjection.subtreePath(of: target)).md"]
        CorpusStore.save(source)

        let moved = try XCTUnwrap(CorpusStore.move(target, under: container))
        XCTAssertEqual(moved.rewrittenDocuments, 1, "the note pointing at it has to be rewritten")

        // `AppModel(isUITesting:)` repoints the corpus at its own throwaway
        // root, so this test's corpus has to be reinstated before loading.
        let app = AppModel(isUITesting: true)
        CorpusStore.rootOverride = root
        app.history = CorpusStore.loadNotes()
        let reloadedSource = try XCTUnwrap(app.history.first { $0.title == "Reunião de kickoff" })

        XCTAssertEqual(reloadedSource.links, ["/inbox/pessoas/marina-souza.md"])
        XCTAssertEqual(app.linkedNotes(of: reloadedSource).map(\.title), ["Marina Souza"])
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    /// Writes a note straight to `relativePath` and loads it back, so the test
    /// controls where it sits. `CorpusStore.save` would place a note it has
    /// never seen under `inbox`, which is right for a new session and wrong for
    /// a fixture.
    @discardableResult
    private func place(_ title: String, at relativePath: String, titleSource: NoteTitleSource = .user) throws -> MemoryNote {
        var value = note(title, titleSource: titleSource)
        let slug = (relativePath as NSString).lastPathComponent
        let parent = (relativePath as NSString).deletingLastPathComponent
        value.archiveFolderName = slug
        value.relativeFolderPath = parent
        let url = root.appendingPathComponent("\(relativePath).md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NoteDocumentWriter.render(value, producer: "cueme/test").write(to: url, atomically: true, encoding: .utf8)
        return value
    }

    // MARK: - AC1

    func testMovingCarriesTheWholeSubtree() throws {
        let acme = try place("Acme", at: "acme")
        let child = try place("Atas", at: "atas")
        try place("Reunião 1", at: "atas/reuniao-1")
        let raw = root.appendingPathComponent("atas/raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: raw.appendingPathComponent("self.m4a"))

        let outcome = try XCTUnwrap(CorpusStore.move(child, under: acme))

        XCTAssertEqual(outcome.toPath, "/acme/atas.md")
        XCTAssertTrue(exists("acme/atas.md"))
        XCTAssertTrue(exists("acme/atas/raw/self.m4a"), "raw/ must travel with the note")
        XCTAssertTrue(exists("acme/atas/reuniao-1.md"), "the subtree must travel with the note")
        XCTAssertFalse(exists("atas.md"))
    }

    // MARK: - AC2

    func testFailedDocumentMoveRestoresTheFolder() throws {
        try place("Origem", at: "origem")
        try place("Filho", at: "origem/filho")

        struct MoveFailed: Error {}
        var attempted: [(URL, URL)] = []

        XCTAssertThrowsError(
            try CorpusStore.moveNoteObjects(
                document: (root.appendingPathComponent("origem.md"), root.appendingPathComponent("destino.md")),
                folder: (
                    root.appendingPathComponent("origem", isDirectory: true),
                    root.appendingPathComponent("destino", isDirectory: true)
                ),
                moving: { from, to in
                    attempted.append((from, to))
                    // Let the folder move through, fail the document move.
                    guard from.pathExtension != "md" else { throw MoveFailed() }
                    try FileManager.default.moveItem(at: from, to: to)
                }
            )
        )

        XCTAssertEqual(attempted.count, 3, "folder out, document attempted, folder back")
        XCTAssertTrue(exists("origem.md"), "the document must stay where it was")
        XCTAssertTrue(exists("origem/filho.md"), "the folder must be put back, with its subtree")
        XCTAssertFalse(exists("destino"), "no half-moved folder may be left behind")
    }

    // MARK: - AC3 and AC4

    func testRenameRewritesInboundLinksAndReportsTheCount() throws {
        let target = try place("Marina Souza", at: "marina-souza")
        for (title, slug) in [("Reunião A", "reuniao-a"), ("Reunião B", "reuniao-b")] {
            var citing = note(title)
            citing.archiveFolderName = slug
            citing.relativeFolderPath = ""
            citing.links = ["/marina-souza.md", "/nao-existe.md"]
            let url = root.appendingPathComponent("\(slug).md")
            try NoteDocumentWriter.render(citing, producer: "cueme/test").write(to: url, atomically: true, encoding: .utf8)
        }

        let outcome = try XCTUnwrap(CorpusStore.rename(target, to: "Marina S"))

        XCTAssertEqual(outcome.toPath, "/marina-s.md")
        XCTAssertEqual(outcome.rewrittenDocuments, 2)
        let reloaded = CorpusStore.loadNotes().filter { $0.title.hasPrefix("Reunião") }
        XCTAssertEqual(reloaded.count, 2)
        for citing in reloaded {
            XCTAssertTrue(citing.links.contains("/marina-s.md"))
            XCTAssertTrue(citing.links.contains("/nao-existe.md"), "a link to nothing must be tolerated, not dropped")
        }
    }

    // MARK: - AC5

    func testGeneratedTitleDoesNotMoveTheFile() throws {
        let generated = try place("Título automático", at: "titulo-automatico", titleSource: .generated)

        // `applyGeneratedTitle` is what post-processing calls, and saving after
        // it must leave the file exactly where it is — otherwise every summary
        // pass would move a file and rewrite the links pointing at it.
        var afterAI = generated
        afterAI.applyGeneratedTitle("Outro título da IA")
        _ = CorpusStore.save(afterAI)

        XCTAssertTrue(exists("titulo-automatico.md"), "a generated title must not move the file")
        XCTAssertFalse(exists("outro-titulo-da-ia.md"))
    }

    // MARK: - AC6

    func testCannotMoveAParentIntoItsOwnChild() throws {
        let parent = try place("Pai", at: "pai")
        let loadedChild = try place("Filho", at: "pai/filho")

        XCTAssertFalse(CorpusStore.canPlace(parent, in: "pai"))
        XCTAssertNil(CorpusStore.move(parent, under: loadedChild))
        XCTAssertTrue(exists("pai.md"), "a refused move must not touch disk")
    }

    // MARK: - AC7

    func testDestinationSlugCollisionIsDisambiguated() throws {
        try place("Alvo", at: "alvo")
        let loadedMover = try place("Alvo", at: "alvo/alvo")

        let outcome = try XCTUnwrap(CorpusStore.move(loadedMover, under: nil))

        XCTAssertEqual(outcome.toPath, "/alvo-2.md")
        XCTAssertTrue(exists("alvo.md"))
        XCTAssertTrue(exists("alvo-2.md"))
    }
}
