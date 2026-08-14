import XCTest
@testable import CueMe

final class MemoryNoteTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeMemoryNoteTests-\(UUID().uuidString)", isDirectory: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - AC1: confidence is quantized where it is assigned, not where it is written

    func testConfidenceIsQuantizedOnAssignment() {
        var takeaway = SessionTakeaway(text: "Pedir propostas", confidence: 0.9412345)
        XCTAssertEqual(try XCTUnwrap(takeaway.confidence), 0.941, accuracy: 1e-12)

        takeaway.confidence = 0.6666666
        XCTAssertEqual(try XCTUnwrap(takeaway.confidence), 0.667, accuracy: 1e-12)

        var decision = MeetingReviewItem(text: "Adotar frota elétrica", confidence: 0.9749999)
        XCTAssertEqual(try XCTUnwrap(decision.confidence), 0.975, accuracy: 1e-12)

        decision.confidence = nil
        XCTAssertNil(decision.confidence)
    }

    // MARK: - AC2/AC3: the short summary is derived, with no intermediate field

    func testShortSummaryComesFromMinutesTopics() {
        var note = Self.blankNote(title: "Estratégia de frota")
        note.minutes = MeetingMinutes(
            overview: "",
            topics: [.init(id: UUID(), title: "Mobilidade", summary: "Troca gradual da frota.", updatedAt: Date())]
        )

        XCTAssertEqual(note.shortSummary, "Mobilidade: Troca gradual da frota.")
    }

    func testShortSummaryPrefersTheOverviewWhenPresent() {
        var note = Self.blankNote(title: "Estratégia de frota")
        note.minutes = MeetingMinutes(
            overview: "A equipe aprovou a migração.",
            topics: [.init(id: UUID(), title: "Mobilidade", summary: "Troca gradual.", updatedAt: Date())]
        )

        XCTAssertEqual(note.shortSummary, "A equipe aprovou a migração.")
    }

    func testShortSummaryFallsBackToTitle() {
        let note = Self.blankNote(title: "Estratégia de frota")

        XCTAssertEqual(note.shortSummary, note.title)
    }

    private static func blankNote(title: String) -> MemoryNote {
        MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            displayTitle: title
        )
    }

    func testMemoryNoteIsTheBaseEntityForWritingAndRecordedExperiences() {
        let note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            noteKind: .journal,
            markdownBody: "Hoje percebi que preciso desacelerar."
        )

        XCTAssertEqual(note.noteKind, .journal)
        XCTAssertEqual(note.noteKind.icon, "book.closed.fill")
        XCTAssertEqual(note.markdownBody, "Hoje percebi que preciso desacelerar.")
        XCTAssertFalse(note.containsRecording)
    }

    /// Integration-level counterpart of `NoteDocumentExternalEditTests`
    /// (T012): proves the canonical-on-external-edit rule holds through the
    /// full `CorpusStore.save` / `loadAll` round trip, not just the reader in
    /// isolation.
    func testNoteMarkdownFrontmatterIsCanonicalWhenEditedOutsideCueMe() throws {
        var note = MemoryNote(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            noteKind: .note,
            markdownBody: "Rascunho inicial",
            labels: ["ideias"]
        )
        note.rename(to: "Ideia inicial")

        let noteURL = try XCTUnwrap(CorpusStore.save(note))
        let saved = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("---\n"))
        XCTAssertTrue(saved.contains("title: Ideia inicial"))
        XCTAssertTrue(saved.contains("tags:"))
        XCTAssertTrue(saved.contains("- ideias"))

        let externallyEdited = saved
            .replacingOccurrences(of: "# Ideia inicial", with: "# Ideia amadurecida")
            .replacingOccurrences(of: "Rascunho inicial", with: "## Hipótese\n\nUm registro soberano do usuário.")
        try externallyEdited.write(to: noteURL, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(CorpusStore.loadNotes().first)
        XCTAssertEqual(loaded.title, "Ideia amadurecida")
        XCTAssertEqual(loaded.labels, ["ideias"])
        XCTAssertTrue(loaded.markdownBody.contains("Um registro soberano do usuário."))
    }

    func testGeneratedTitleNeverOverwritesAUserRename() {
        var note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
        )

        note.applyGeneratedTitle("Plano de lançamento")
        XCTAssertEqual(note.title, "Plano de lançamento")
        XCTAssertEqual(note.titleSource, .generated)

        note.rename(to: "Lançamento do CueMe 1.0")
        note.applyGeneratedTitle("Título tardio da IA")

        XCTAssertEqual(note.title, "Lançamento do CueMe 1.0")
        XCTAssertEqual(note.titleSource, .user)
    }

    func testLabelsAreNormalizedAndDeduplicated() {
        var note = MemoryNote(
            startedAt: Date(), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: []
        )

        note.setLabels([" Trabalho ", "trabalho", "PESSOAL", ""])

        XCTAssertEqual(note.labels, ["pessoal", "trabalho"])
    }

    /// A container is an ordinary note, so the same rule applies to it as to
    /// any other: what the file says wins. Renaming one in an editor must
    /// survive a reload, and its children must still resolve under it.
    func testContainerNoteRenamedOutsideCueMeKeepsItsChildren() throws {
        var container = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], origin: .written,
            displayTitle: "Projeto original", noteKind: .note, titleSource: .user
        )
        container.relativeFolderPath = ""
        container.archiveFolderName = "projeto-original"
        var child = container
        child = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 2_000), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], origin: .written,
            displayTitle: "Ata", noteKind: .note, titleSource: .user
        )
        child.relativeFolderPath = "projeto-original"
        child.archiveFolderName = "ata"

        let containerURL = root.appendingPathComponent("projeto-original.md")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("projeto-original", isDirectory: true),
            withIntermediateDirectories: true
        )
        try NoteDocumentWriter.render(container, producer: "cueme/test")
            .write(to: containerURL, atomically: true, encoding: .utf8)
        try NoteDocumentWriter.render(child, producer: "cueme/test")
            .write(to: root.appendingPathComponent("projeto-original/ata.md"), atomically: true, encoding: .utf8)

        let edited = try String(contentsOf: containerURL, encoding: .utf8)
            .replacingOccurrences(of: "Projeto original", with: "Projeto soberano")
        try edited.write(to: containerURL, atomically: true, encoding: .utf8)

        let loaded = CorpusStore.loadNotes()
        let reloadedContainer = try XCTUnwrap(loaded.first { $0.archiveFolderName == "projeto-original" })

        XCTAssertEqual(reloadedContainer.title, "Projeto soberano")
        XCTAssertEqual(reloadedContainer.id, container.id, "the id lives in the file, not in the path")
        XCTAssertEqual(
            NoteTreeProjection.children(in: loaded, of: reloadedContainer).map(\.title),
            ["Ata"],
            "renaming the title must not detach the children, which hang off the path"
        )
    }
}
