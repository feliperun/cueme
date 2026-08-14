import XCTest
@testable import CueMe

/// `index.md` is how an agent discovers the tree without loading it whole, so
/// what it lists — and when it is left alone — is the contract.
final class IndexDocumentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func indexedNote(_ title: String, at path: String, goal: String = "") -> MemoryNote {
        var value = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_060),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: goal,
            transcript: [],
            coachCards: [],
            displayTitle: title,
            titleSource: .user
        )
        value.archiveFolderName = (path as NSString).lastPathComponent
        value.relativeFolderPath = (path as NSString).deletingLastPathComponent
        return value
    }

    private func indexFile(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private var corpus: [MemoryNote] {
        [
            indexedNote("Acme", at: "acme", goal: "Contexto e histórico da conta Acme."),
            indexedNote("Inbox", at: "inbox"),
            indexedNote("Pessoas", at: "pessoas", goal: "Quem aparece nas reuniões."),
            indexedNote("Atas", at: "acme/atas", goal: "Registro das reuniões da conta."),
            indexedNote("Proposta comercial", at: "acme/proposta-comercial"),
        ]
    }

    // MARK: AC4 — direct children, with descriptions, sorted by title

    func testIndexListsDirectChildrenWithDescriptions() throws {
        CorpusStore.writeIndexes(for: corpus)

        XCTAssertEqual(try indexFile("acme/index.md"), """
        # Acme

        * [Atas](atas.md) - Registro das reuniões da conta.
        * [Proposta comercial](proposta-comercial.md)

        """)
        XCTAssertFalse(
            try indexFile("index.md").contains("atas.md"),
            "the root index lists its own children, not the whole tree"
        )
    }

    // MARK: AC5 — only the root carries okf_version

    func testOnlyRootIndexCarriesOkfVersion() throws {
        CorpusStore.writeIndexes(for: corpus)

        XCTAssertEqual(try indexFile("index.md"), """
        ---
        okf_version: "0.2"
        ---

        # Notas

        * [Acme](acme.md) - Contexto e histórico da conta Acme.
        * [Inbox](inbox.md)
        * [Pessoas](pessoas.md) - Quem aparece nas reuniões.

        """)
        XCTAssertFalse(try indexFile("acme/index.md").contains("okf_version"))
        XCTAssertFalse(try indexFile("acme/index.md").hasPrefix("---"))
    }

    // MARK: AC6 — no description means link only

    func testChildWithoutDescriptionIsListedBare() {
        let entries = IndexDocument.entries(in: corpus, directory: "")

        XCTAssertEqual(entries.map(\.title), ["Acme", "Inbox", "Pessoas"])
        XCTAssertNil(entries.first { $0.title == "Inbox" }?.description)
        XCTAssertEqual(
            IndexDocument.render(heading: "Notas", entries: entries, isRoot: false),
            """
            # Notas

            * [Acme](acme.md) - Contexto e histórico da conta Acme.
            * [Inbox](inbox.md)
            * [Pessoas](pessoas.md) - Quem aparece nas reuniões.

            """
        )
    }

    // MARK: AC3 — an unchanged level is not rewritten

    func testUnchangedIndexIsNotRewritten() throws {
        let first = CorpusStore.writeIndexes(for: corpus)
        XCTAssertEqual(Set(first), ["index.md", "acme/index.md"])

        XCTAssertTrue(
            CorpusStore.writeIndexes(for: corpus).isEmpty,
            "nothing changed, so nothing may be written — otherwise every load is a diff"
        )

        var changed = corpus
        changed.append(indexedNote("Nova ata", at: "acme/nova-ata"))
        XCTAssertEqual(
            CorpusStore.writeIndexes(for: changed),
            ["acme/index.md"],
            "only the level that actually changed is rewritten"
        )
    }

    func testALevelWithNoChildrenGetsNoIndex() {
        CorpusStore.writeIndexes(for: corpus)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("inbox/index.md").path),
            "a leaf has no children to index, and no sibling folder either"
        )
    }
}
