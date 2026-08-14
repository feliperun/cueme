import XCTest

/// The premise of the whole OKF refactor is that the Markdown *is* the note:
/// edit it anywhere and CueMe agrees. These drive a real corpus on disk through
/// `CUEME_UI_CORPUS_ROOT` rather than the in-memory fixture, because nothing
/// else can prove it.
@MainActor
final class CueMeCorpusE2ETests: XCTestCase {
    private var corpus: URL!

    override func setUpWithError() throws {
        corpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeCorpusE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: corpus)
        corpus = nil
    }

    // MARK: - Fixture

    private static let acmeID = "aaaaaaaa-0000-4000-8000-000000000001"
    private static let atasID = "aaaaaaaa-0000-4000-8000-000000000002"

    private func corpusNoteMarkdown(
        id: String,
        title: String,
        body: String
    ) -> String {
        """
        ---
        type: Note
        title: \(title)
        description: ""
        created_at: "2026-08-08T14:30:11.000Z"
        updated_at: "2026-08-08T14:30:11.000Z"
        generated:
          by: cueme/e2e
          at: "2026-08-08T14:30:11.000Z"
        x_cueme_id: \(id)
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

    private func writeCorpusDocument(_ markdown: String, to relativePath: String) throws {
        let url = corpus.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func launchAgainstCorpus() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CUEME_UI_TESTING"] = "1"
        app.launchEnvironment["CUEME_UI_CORPUS_ROOT"] = corpus.path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    /// Activation reloads the corpus, but synthesizing a real app switch from a
    /// test is at the mercy of the window server. The refresh control is the
    /// same reload, asked for explicitly — deterministic, and a real affordance
    /// rather than something that exists only for tests.
    private func reactivateForCorpusReload(_ app: XCUIApplication) {
        let refresh = app.buttons["library.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.click()
    }

    private func waitForCorpusCondition(
        _ description: String,
        timeout: TimeInterval = 8,
        _ condition: @escaping () -> Bool
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        expectation.expectationDescription = description
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - AC1, AC2 — the file wins

    func testExternallyEditedNoteMarkdownWinsInTheUI() throws {
        try writeCorpusDocument(
            corpusNoteMarkdown(
                id: Self.acmeID,
                title: "Acme",
                body: "- [ ] Fechar contrato\n"
            ),
            to: "acme.md"
        )

        let app = launchAgainstCorpus()
        defer { app.terminate() }

        let row = app.buttons["session.\(Self.acmeID.uppercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the corpus on disk is what the library shows")
        row.click()

        let pending = app.buttons["Fechar contrato"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertEqual(pending.value as? String, "unchecked")

        // The edit is made outside CueMe — that is the entire point.
        try writeCorpusDocument(
            corpusNoteMarkdown(
                id: Self.acmeID,
                title: "Acme Corp",
                body: "- [x] Fechar contrato\n"
            ),
            to: "acme.md"
        )

        reactivateForCorpusReload(app)

        XCTAssertTrue(
            waitForCorpusCondition("the library shows the title from the file") {
                row.exists && row.label.contains("Acme Corp")
            },
            "AC1: a title edited on disk must win over what CueMe had in memory"
        )
        XCTAssertTrue(
            waitForCorpusCondition("the pending item is checked") {
                app.buttons["Fechar contrato"].value as? String == "checked"
            },
            "AC2: ticking a box in an editor must be visible in the app"
        )
    }

    // MARK: - AC3 — nesting moves the file

    func testNestingANoteMovesItOnDisk() throws {
        try writeCorpusDocument(corpusNoteMarkdown(id: Self.acmeID, title: "Acme", body: "Conta.\n"), to: "acme.md")
        try writeCorpusDocument(corpusNoteMarkdown(id: Self.atasID, title: "Atas", body: "Reuniões.\n"), to: "atas.md")

        let app = launchAgainstCorpus()
        defer { app.terminate() }

        let parent = app.buttons["tree.container.\(Self.acmeID.uppercased())"]
        let child = app.buttons["tree.container.\(Self.atasID.uppercased())"]
        XCTAssertTrue(parent.waitForExistence(timeout: 8))
        XCTAssertTrue(child.waitForExistence(timeout: 5))

        child.press(forDuration: 0.6, thenDragTo: parent)

        let moved = corpus.appendingPathComponent("acme/atas.md")
        XCTAssertTrue(
            waitForCorpusCondition("the child document moved under the parent") {
                FileManager.default.fileExists(atPath: moved.path)
            },
            "AC3: nesting in the tree has to move the file, not just the row"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: corpus.appendingPathComponent("atas.md").path),
            "the document must not be left behind at the old address"
        )

        let disclosure = app.buttons["tree.note.disclosure.\(Self.acmeID.uppercased())"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForCorpusCondition("the tree shows it nested") {
                disclosure.click()
                return app.buttons["tree.note.\(Self.atasID.uppercased())"].exists
                    || app.buttons["tree.container.\(Self.atasID.uppercased())"].exists
            }
        )
    }

    // MARK: - The reserved files are written for a real corpus

    func testAgentsFileAndIndexAreWrittenIntoTheCorpus() throws {
        try writeCorpusDocument(corpusNoteMarkdown(id: Self.acmeID, title: "Acme", body: "Conta.\n"), to: "acme.md")

        let app = launchAgainstCorpus()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["session.\(Self.acmeID.uppercased())"].waitForExistence(timeout: 8))

        XCTAssertTrue(
            waitForCorpusCondition("AGENTS.md and index.md exist") {
                FileManager.default.fileExists(atPath: self.corpus.appendingPathComponent("AGENTS.md").path)
                    && FileManager.default.fileExists(atPath: self.corpus.appendingPathComponent("index.md").path)
            }
        )
        let index = try String(contentsOf: corpus.appendingPathComponent("index.md"), encoding: .utf8)
        XCTAssertTrue(index.contains("* [Acme](acme.md)"))
        XCTAssertTrue(index.hasPrefix("---\nokf_version: \"0.2\""))
    }
}
