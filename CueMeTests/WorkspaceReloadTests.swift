import XCTest
@testable import CueMe

/// The premise of the OKF corpus is that the file wins. `reloadWorkspaceFromDisk`
/// is the only path that lets an edit made outside CueMe reach the UI, so it is
/// proved here rather than only in the UI suite.
@MainActor
final class WorkspaceReloadTests: XCTestCase {
    private var corpus: URL!

    override func setUpWithError() throws {
        corpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeWorkspaceReload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: corpus)
        corpus = nil
    }

    private static let noteID = "aaaaaaaa-0000-4000-8000-000000000001"

    private func document(title: String, body: String) -> String {
        """
        ---
        type: Note
        title: \(title)
        created_at: "2026-08-08T14:30:11.000Z"
        updated_at: "2026-08-08T14:30:11.000Z"
        generated:
          by: cueme/test
          at: "2026-08-08T14:30:11.000Z"
        x_cueme_id: \(Self.noteID)
        x_cueme_kind: note
        x_cueme_mode: recording
        x_cueme_origin: written
        x_cueme_training: false
        x_cueme_title_source: user
        x_cueme_ended_at: "2026-08-08T14:30:11.000Z"
        x_cueme_lang:
          conversation: pt-BR
          native: pt-BR
        ---

        # \(title)

        \(body)
        """
    }

    private func writeDocument(title: String, body: String) throws {
        try document(title: title, body: body)
            .write(to: corpus.appendingPathComponent("acme.md"), atomically: true, encoding: .utf8)
    }

    /// Puts the model in the state the app is in after launching against a real
    /// corpus: history loaded from disk, reload armed, stamp recorded.
    private func launched() throws -> AppModel {
        let app = AppModel(isUITesting: true)
        CorpusStore.rootOverride = corpus
        app.reloadFromDiskEnabled = true
        app.history = CorpusStore.loadNotes()
        app.lastCorpusLoad = CorpusStore.latestModification()
        return app
    }

    func testAnExternalEditToTheMarkdownReachesTheModel() throws {
        try writeDocument(title: "Acme", body: "- [ ] Fechar contrato")
        let app = try launched()
        XCTAssertEqual(app.history.map(\.title), ["Acme"])

        try writeDocument(title: "Acme Corp", body: "- [x] Fechar contrato")
        app.reloadWorkspaceFromDisk()

        XCTAssertEqual(app.history.map(\.title), ["Acme Corp"], "the file wins")
        XCTAssertTrue(
            try XCTUnwrap(app.history.first).markdownBody.contains("- [x] Fechar contrato"),
            "a box ticked in an editor has to arrive too"
        )
    }

    func testAnUnchangedCorpusIsNotReread() throws {
        try writeDocument(title: "Acme", body: "corpo")
        let app = try launched()
        app.history = []

        app.reloadWorkspaceFromDisk()

        XCTAssertTrue(app.history.isEmpty, "nothing on disk is newer, so nothing may be read")
    }

    func testTheReloadStaysOffWhenNotArmed() throws {
        try writeDocument(title: "Acme", body: "corpo")
        let app = try launched()
        app.reloadFromDiskEnabled = false
        app.history = []

        try writeDocument(title: "Acme Corp", body: "corpo")
        app.reloadWorkspaceFromDisk()

        XCTAssertTrue(app.history.isEmpty, "the deterministic UI-test fixture must never be replaced")
    }

    func testABusySessionIsNeverInterruptedByAReload() throws {
        try writeDocument(title: "Acme", body: "corpo")
        let app = try launched()
        app.sessionState = .preparing
        app.history = []

        try writeDocument(title: "Acme Corp", body: "corpo")
        app.reloadWorkspaceFromDisk()

        XCTAssertTrue(app.history.isEmpty)
    }
}
