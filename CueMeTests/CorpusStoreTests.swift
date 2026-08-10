import XCTest
@testable import CueMe

/// AC1–AC6 of `specs/okf-corpus/tasks/T013-corpus-store.md`. AC7 (recording
/// audio lands in `raw/`) lives in `AudioImportAndKnowledgeTests` alongside
/// the rest of the audio-import suite.
final class CorpusStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeCorpusStoreTests-\(UUID().uuidString)", isDirectory: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Test double

    /// Wraps the real filesystem while counting how many times each method is
    /// called, so AC1 can be proven by call count instead of wall-clock
    /// timing (constitution.md §4 forbids the latter).
    private final class SpyReading: NoteTreeFileReading {
        private let real = DiskNoteTreeReading()
        private(set) var contentReadURLs: [URL] = []
        private(set) var listingURLs: [URL] = []

        func noteFileBaseNames(at url: URL) -> Set<String> {
            listingURLs.append(url)
            return real.noteFileBaseNames(at: url)
        }

        func subdirectoryNames(at url: URL) -> Set<String> {
            listingURLs.append(url)
            return real.subdirectoryNames(at: url)
        }

        func contents(of url: URL) -> String? {
            contentReadURLs.append(url)
            return real.contents(of: url)
        }
    }

    // MARK: - Fixture helpers (real writers, never hand-typed frontmatter)

    private func makeNote(title: String, turns: [TranscriptLine] = []) -> MemoryNote {
        MemoryNote(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: turns,
            coachCards: [],
            displayTitle: title,
            titleSource: .user
        )
    }

    @discardableResult
    private func writeNoteFile(_ note: MemoryNote, at relativePath: String) throws -> URL {
        let url = root.appendingPathComponent("\(relativePath).md")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try NoteDocumentWriter.render(note, producer: "cueme/test").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeTranscriptFile(_ note: MemoryNote, at relativePath: String) throws {
        guard let markdown = TranscriptDocument.render(note, producer: "cueme/test") else {
            XCTFail("fixture note has no loaded transcript to render")
            return
        }
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - AC1

    func testLoadReadsOnlyNoteFiles() throws {
        let turn = TranscriptLine(speaker: .self, text: "Fala.", isFinal: true, ts: Date(timeIntervalSince1970: 1_704_110_401))
        let a = makeNote(title: "A", turns: [turn])
        try writeNoteFile(a, at: "a")
        try writeTranscriptFile(a, at: "a/raw/transcript.md")
        try Data("fake audio".utf8).write(to: root.appendingPathComponent("a/raw/self.m4a"))
        try writeNoteFile(makeNote(title: "B"), at: "a/b")

        let spy = SpyReading()
        let result = NoteTree.discover(at: root, reading: spy)

        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(spy.contentReadURLs.count, 2, "expected exactly one read per note file")
        XCTAssertTrue(
            spy.contentReadURLs.allSatisfy { !$0.path.contains("/raw/") },
            "must never read inside raw/"
        )
        XCTAssertTrue(
            spy.listingURLs.allSatisfy { !$0.path.hasSuffix("/raw") },
            "must never list raw/'s own contents"
        )
    }

    // MARK: - AC2

    func testOrphanFolderKeepsItsChildren() throws {
        // "acme/" exists with no sibling "acme.md" — an inconsistency, not a
        // data loss: "acme/atas.md" must still load.
        try writeNoteFile(makeNote(title: "Atas"), at: "acme/atas")

        let result = NoteTree.discover(at: root, reading: DiskNoteTreeReading())

        XCTAssertEqual(result.notes.map(\.title), ["Atas"])
        XCTAssertEqual(result.orphanFolders, ["acme"])

        let loaded = CorpusStore.loadNotes()
        XCTAssertEqual(loaded.map(\.title), ["Atas"])
    }

    // MARK: - AC3

    func testEmptySiblingFolderIsRemoved() throws {
        try writeNoteFile(makeNote(title: "Atas"), at: "atas")
        try writeNoteFile(makeNote(title: "Reunião 1"), at: "atas/reuniao-1")

        let child = try XCTUnwrap(CorpusStore.loadNotes().first { $0.title == "Reunião 1" })
        XCTAssertEqual(child.relativeFolderPath, "atas")
        XCTAssertEqual(child.archiveFolderName, "reuniao-1")

        CorpusStore.delete(child)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("atas/reuniao-1.md").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("atas").path),
            "atas/ lost its last child and had no raw/, so it must be removed"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("atas.md").path),
            "only the child was deleted — atas.md itself must remain"
        )
    }

    // MARK: - AC4

    func testForeignMarkdownIsIgnored() throws {
        let foreign = root.appendingPathComponent("leia-me.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Um arquivo que não é do CueMe\n\nSem frontmatter nenhum.".write(
            to: foreign, atomically: true, encoding: .utf8
        )
        try writeNoteFile(makeNote(title: "A"), at: "a")

        let notes = CorpusStore.loadNotes()

        XCTAssertEqual(notes.map(\.title), ["A"])
    }

    // MARK: - AC5

    func testTranscriptLoadsOnDemand() throws {
        let turns = (0..<2).map {
            TranscriptLine(
                speaker: .self, text: "Fala \($0).", isFinal: true,
                ts: Date(timeIntervalSince1970: 1_704_110_401 + Double($0))
            )
        }
        let note = makeNote(title: "A", turns: turns)
        try writeNoteFile(note, at: "a")
        try writeTranscriptFile(note, at: "a/raw/transcript.md")

        let notLoaded = try XCTUnwrap(CorpusStore.loadNotes().first)
        XCTAssertFalse(notLoaded.transcript.isLoaded)
        XCTAssertEqual(notLoaded.transcript.turnCount, 2)

        let loaded = CorpusStore.loadTranscript(for: notLoaded)
        XCTAssertTrue(loaded.transcript.isLoaded)
        XCTAssertEqual(loaded.transcript.turnCount, 2)
    }

    // MARK: - AC6

    func testDeleteRemovesTheWholeSubtree() throws {
        try writeNoteFile(makeNote(title: "Acme"), at: "acme")
        try writeNoteFile(makeNote(title: "Atas"), at: "acme/atas")
        try writeNoteFile(makeNote(title: "Reunião 1"), at: "acme/atas/reuniao-1")

        let acme = try XCTUnwrap(CorpusStore.loadNotes().first { $0.title == "Acme" })

        CorpusStore.delete(acme)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("acme.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("acme").path))
    }

    // MARK: - save() / resolvingLocation()

    func testSaveOfAFreshNoteIsBornUnderInbox() throws {
        let note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: []
        )

        let url = try XCTUnwrap(CorpusStore.save(note))

        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "inbox")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("inbox.md").path))

        let reloaded = try XCTUnwrap(CorpusStore.loadNotes().first { $0.id == note.id })
        XCTAssertEqual(reloaded.relativeFolderPath, "inbox")
    }

    func testResaveOfAnAlreadyPlacedNoteStaysInPlace() throws {
        let note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: []
        )
        let first = CorpusStore.resolvingLocation(note)
        _ = CorpusStore.save(first)

        var edited = first
        edited.goal = "Objetivo atualizado"
        let second = try XCTUnwrap(CorpusStore.save(edited))

        XCTAssertEqual(CorpusStore.noteURL(for: first).standardizedFileURL, second.standardizedFileURL)
        XCTAssertEqual(CorpusStore.loadNotes().filter { $0.id == note.id }.count, 1)
    }
}
