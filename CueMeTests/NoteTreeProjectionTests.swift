import XCTest
@testable import CueMe

/// The sidebar tree is the corpus tree. There is no project entity, so every
/// relationship it draws comes from where a note sits.
@MainActor
final class NoteTreeProjectionTests: XCTestCase {
    private nonisolated(unsafe) var previousArchive: URL?
    private nonisolated(unsafe) var previousInbox: URL?
    private let uiTestArchive = UITestFixtures.uiTestRoot

    override func setUp() {
        super.setUp()
        previousArchive = CorpusStore.rootOverride
        previousInbox = ExternalAudioInbox.rootOverride
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: uiTestArchive)
        try? FileManager.default.removeItem(
            at: UITestFixtures.semanticIndexURL(at: uiTestArchive)
                .deletingLastPathComponent().deletingLastPathComponent()
        )
        CorpusStore.rootOverride = previousArchive
        ExternalAudioInbox.rootOverride = previousInbox
        previousArchive = nil
        previousInbox = nil
        super.tearDown()
    }

    private func note(_ title: String, at path: String, startedAt: Date = Date(timeIntervalSince1970: 1_000)) -> MemoryNote {
        var value = MemoryNote(
            startedAt: startedAt,
            endedAt: startedAt,
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

    func testChildrenComeFromThePathAndSortNewestFirst() {
        let acme = note("Acme", at: "acme")
        let older = note("Antiga", at: "acme/antiga", startedAt: Date(timeIntervalSince1970: 1_000))
        let newer = note("Recente", at: "acme/recente", startedAt: Date(timeIntervalSince1970: 9_000))
        let elsewhere = note("Fora", at: "outra/fora")
        let history = [acme, older, newer, elsewhere]

        let children = NoteTreeProjection.children(in: history, of: acme)

        XCTAssertEqual(children.map(\.title), ["Recente", "Antiga"])
    }

    func testSubtreeReachesEveryDepthAndIncludesTheNoteItself() {
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "acme/atas")
        let deep = note("Reunião", at: "acme/atas/reuniao")
        let sibling = note("Outro", at: "outro")
        let history = [acme, atas, deep, sibling]

        let subtree = NoteTreeProjection.subtree(in: history, of: acme)

        XCTAssertEqual(Set(subtree.map(\.title)), ["Acme", "Atas", "Reunião"])
    }

    func testRootNotesAreTheOnesWithNoParentDirectory() {
        let history = [note("Beta", at: "beta"), note("Alfa", at: "alfa"), note("Filha", at: "alfa/filha")]

        XCTAssertEqual(NoteTreeProjection.rootNotes(in: history).map(\.title), ["Alfa", "Beta"])
    }

    func testLiveChildOnlyBelongsToTheActiveNodeWhileRunning() {
        let id = UUID()
        let other = UUID()

        XCTAssertTrue(NoteTreeProjection.showsLiveChild(for: id, activeParentNoteID: id, isRunning: true))
        XCTAssertFalse(NoteTreeProjection.showsLiveChild(for: id, activeParentNoteID: id, isRunning: false))
        XCTAssertFalse(NoteTreeProjection.showsLiveChild(for: id, activeParentNoteID: other, isRunning: true))
        XCTAssertFalse(NoteTreeProjection.showsLiveChild(for: id, activeParentNoteID: nil, isRunning: true))
    }

    // MARK: - Wired through AppModel

    func testSelectingATreeRecordScopesTheListToItsContainer() {
        let app = AppModel(isUITesting: true)
        let child = try? XCTUnwrap(app.history.first { $0.title == "Estratégia de frota elétrica" })
        guard let child else { return XCTFail("fixture note missing") }

        app.selectNoteTreeRecord(child)

        let container = app.history.first { $0.title == "Projeto Mobilidade" }
        XCTAssertEqual(app.librarySubtreeNoteID, container?.id)
        XCTAssertEqual(app.selectedSessionID, child.id)
        XCTAssertEqual(app.historySearch, "")
    }

    func testAContainerIsForcedOpenWhileOneOfItsDescendantsIsSelected() {
        let app = AppModel(isUITesting: true)
        guard let container = app.history.first(where: { $0.title == "Projeto Mobilidade" }),
              let child = app.history.first(where: { $0.title == "Levantamento de custos" }) else {
            return XCTFail("fixture tree missing")
        }

        app.selectSession(child.id)

        XCTAssertTrue(app.isNoteForcedExpanded(container))
        XCTAssertTrue(app.isNoteExpanded(container, explicitly: []))
    }

    func testExplicitExpansionCollapsesWhenNothingForcesItOpen() {
        let app = AppModel(isUITesting: true)
        guard let container = app.history.first(where: { $0.title == "Projeto Mobilidade" }) else {
            return XCTFail("fixture tree missing")
        }
        app.selectLibrarySection(.all)
        app.selectedSessionID = nil

        XCTAssertFalse(app.isNoteForcedExpanded(container))
        XCTAssertTrue(app.isNoteExpanded(container, explicitly: [container.id]))
        XCTAssertFalse(app.isNoteExpanded(container, explicitly: []))
    }

    /// The index is a derived cache, so it lives beside the corpus and never
    /// inside it — otherwise `CorpusStore.loadNotes()` would walk over it.
    /// AC7: the E2E scenario drives the tree through these strings, so they are
    /// derived from the note id and built in exactly one place.
    func testRowsExposeStableIdentifiers() {
        let id = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

        XCTAssertEqual(NoteTreeIdentifier.container(id), "tree.container.\(id.uuidString)")
        XCTAssertEqual(NoteTreeIdentifier.child(id), "tree.note.\(id.uuidString)")
        XCTAssertEqual(NoteTreeIdentifier.disclosure(id), "tree.note.disclosure.\(id.uuidString)")
        XCTAssertEqual(NoteTreeIdentifier.rootDropZone, "tree.root.dropzone")
        XCTAssertEqual(
            Set([
                NoteTreeIdentifier.container(id),
                NoteTreeIdentifier.child(id),
                NoteTreeIdentifier.disclosure(id),
            ]).count,
            3,
            "a container and its child row must never collide"
        )
    }

    /// The hover highlight asks the same question the drop does, so an invalid
    /// destination is refused before the user lets go — not silently after.
    func testHoverFeedbackAgreesWithTheDropDecision() {
        let app = AppModel(isUITesting: true)
        let acme = note("Acme", at: "acme")
        let atas = note("Atas", at: "acme/atas")
        app.history = [acme, atas]

        XCTAssertFalse(app.acceptsNoteDrop(onto: acme.id), "nothing is being dragged")

        app.draggingNoteID = atas.id
        XCTAssertFalse(app.acceptsNoteDrop(onto: acme.id), "already inside Acme")
        XCTAssertTrue(app.acceptsNoteDrop(onto: nil), "the root unnests it")

        app.draggingNoteID = acme.id
        XCTAssertFalse(app.acceptsNoteDrop(onto: atas.id), "a parent cannot enter its own child")
        XCTAssertFalse(app.acceptsNoteDrop(onto: nil), "already at the root")
    }

    func testUITestAppCreatesSemanticIndexBesideItsIsolatedCorpus() {
        let app = AppModel(isUITesting: true)
        let index = app.semanticMemoryIndexURLForTesting.standardizedFileURL
        let corpus = uiTestArchive.standardizedFileURL

        XCTAssertFalse(index.path.hasPrefix(corpus.path + "/"))
        XCTAssertEqual(
            index.path,
            UITestFixtures.semanticIndexURL(at: corpus).standardizedFileURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
    }

    func testPastNotesSearchUsesTheInjectedIsolatedSemanticIndex() {
        let app = AppModel(isUITesting: true)
        let fixtureRecordID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        app.activeParentNoteID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

        let results = app.searchPastNotes("carro sustentável")

        XCTAssertTrue(results.contains { $0.recordID == fixtureRecordID })
        XCTAssertTrue(app.semanticMemoryIndexedSessionIDsForTesting.contains(fixtureRecordID))
    }
}
