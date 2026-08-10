import XCTest
@testable import CueMe

/// App activation asks for a reload every time. Stat is cheap, reading the tree
/// is not — so the question "did anything change" has to be answerable without
/// opening a single file.
final class CorpusReloadTests: XCTestCase {
    private var corpusRoot: URL!

    override func setUpWithError() throws {
        corpusRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeReload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: corpusRoot, withIntermediateDirectories: true)
        CorpusStore.rootOverride = corpusRoot
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: corpusRoot)
        corpusRoot = nil
    }

    private func storedNote(_ title: String) -> MemoryNote {
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
        value = CorpusStore.resolvingLocation(value)
        CorpusStore.save(value)
        return value
    }

    private func stamp(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: AC2 — nothing newer means nothing read

    func testUnchangedCorpusSkipsReload() throws {
        _ = storedNote("Acme")
        let seen = try XCTUnwrap(CorpusStore.latestModification())

        XCTAssertFalse(
            CorpusStore.corpusChanged(since: seen),
            "no `.md` is newer than the last load, so there is nothing to read"
        )
        XCTAssertFalse(CorpusStore.corpusChanged(since: seen.addingTimeInterval(60)))
    }

    // MARK: AC4 — an edit made outside CueMe is seen

    func testExternalChangeTriggersReload() throws {
        let note = storedNote("Acme")
        let seen = try XCTUnwrap(CorpusStore.latestModification())
        let url = CorpusStore.noteURL(for: note)

        // An explicit mtime, never a sleep waiting for the clock to move.
        try stamp(url, seen.addingTimeInterval(5))

        XCTAssertTrue(CorpusStore.corpusChanged(since: seen))
        XCTAssertEqual(
            try XCTUnwrap(CorpusStore.latestModification()).timeIntervalSince1970,
            seen.addingTimeInterval(5).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testTheFirstLoadAlwaysReads() {
        _ = storedNote("Acme")

        XCTAssertTrue(CorpusStore.corpusChanged(since: nil), "no stamp yet — read everything")
    }

    func testAnEmptyCorpusIsNotAChange() throws {
        let anchor = Date(timeIntervalSince1970: 5_000)

        XCTAssertFalse(
            CorpusStore.corpusChanged(since: anchor),
            "there is nothing on disk, so there is nothing newer"
        )
    }

    /// The stat walk must not be fooled by files that are not notes: only `.md`
    /// carries durable content.
    func testANewAudioFileIsNotACorpusChange() throws {
        let note = storedNote("Acme")
        let seen = try XCTUnwrap(CorpusStore.latestModification())
        let raw = CorpusStore.noteFolder(for: note).appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let audio = raw.appendingPathComponent("self.m4a")
        try Data([0x00]).write(to: audio)
        try stamp(audio, seen.addingTimeInterval(60))

        XCTAssertFalse(CorpusStore.corpusChanged(since: seen))
    }
}
