import XCTest
@testable import CueMe

final class SessionArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeArchiveTests-\(UUID().uuidString)", isDirectory: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    /// `CorpusStore.save` delegates to `CorpusStore`: the note lands under the
    /// default "inbox" note as an OKF concept document, and nothing else. The
    /// `session.json` sidecar is gone — the Markdown is the only durable copy.
    func testSaveWritesTheNoteAsAnOKFDocumentUnderInbox() throws {
        let startedAt = Date(timeIntervalSince1970: 1_704_110_400)
        let record = MemoryNote(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(90),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "en-US",
            goal: "Definir próximos passos",
            transcript: [],
            coachCards: [],
            takeaways: [.init(text: "Enviar cronograma")],
            displayTitle: "Alinhamento de entrega",
            titleSource: .user
        )

        // Resolved once and reused — `resolvingLocation` is deterministic only
        // relative to what is already on disk, so calling it again after the
        // save below (which changes what's on disk) would compute a
        // different, colliding slug.
        let resolved = CorpusStore.resolvingLocation(record)
        let noteURL = try XCTUnwrap(CorpusStore.save(resolved))

        XCTAssertEqual(noteURL.deletingLastPathComponent().lastPathComponent, "inbox")
        let folder = CorpusStore.noteFolder(for: resolved)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("session.json").path),
            "saving a note must not create a JSON sidecar"
        )

        let markdown = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("---\n"))
        XCTAssertTrue(markdown.contains("type: Note"))
        XCTAssertTrue(markdown.contains("title: Alinhamento de entrega"))
        XCTAssertTrue(markdown.contains("# Alinhamento de entrega"))
        XCTAssertTrue(markdown.contains("- [ ] Enviar cronograma"))

        // loadAll() also surfaces the "inbox" note itself now — it is an
        // ordinary note new sessions are born under, not a hidden container.
        XCTAssertTrue(CorpusStore.loadNotes().map(\.id).contains(record.id))
    }

    func testFolderNameIsStableAndPortable() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let date = Date(timeIntervalSince1970: 1_704_110_400)

        let first = SessionArchive.folderName(startedAt: date, id: id)
        let second = SessionArchive.folderName(startedAt: date, id: id)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix("_12345678"))
        XCTAssertFalse(first.contains("/"))
    }
}
