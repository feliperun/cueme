import XCTest
@testable import CueMe

/// Auto-update means the user never chooses the moment they get this build. If
/// it lands on an archive that has not been migrated, everything still living
/// in `session.json` — transcripts, coach cards, minutes, evidence — is
/// invisible to this build and would be dropped by the first save. So the app
/// reads nothing and writes nothing until the migration has run (ADR 0049).
final class LegacyArchiveGuardTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeLegacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func writeLegacyNote(sidecar: Bool) throws {
        let folder = root.appendingPathComponent("_Inbox/2026-01-01-abc", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\ntitle: Antiga\ntype: Note\n---\n\n# Antiga\n"
            .write(to: folder.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        if sidecar {
            try "{}".write(to: folder.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
        }
    }

    private func newNote() -> MemoryNote {
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
            displayTitle: "Nova",
            titleSource: .user
        )
    }

    func testASessionSidecarMarksTheArchiveAsUnmigrated() throws {
        try writeLegacyNote(sidecar: true)

        XCTAssertTrue(CorpusStore.holdsLegacyArchive())
    }

    /// `note.md` inside a folder is the old shape even without the sidecar —
    /// an OKF note is `<slug>.md` beside its folder, never inside it.
    func testALegacyNoteDocumentIsEnoughToRecognizeIt() throws {
        try writeLegacyNote(sidecar: false)

        XCTAssertTrue(CorpusStore.holdsLegacyArchive())
    }

    func testAMigratedCorpusIsNotFlagged() throws {
        try "---\ntype: Note\ntitle: Acme\n---\n\n# Acme\n"
            .write(to: root.appendingPathComponent("acme.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("acme/raw", isDirectory: true), withIntermediateDirectories: true
        )
        try "# Transcrição\n"
            .write(to: root.appendingPathComponent("acme/raw/transcript.md"), atomically: true, encoding: .utf8)

        XCTAssertFalse(CorpusStore.holdsLegacyArchive())
    }

    func testAnEmptyArchiveIsNotFlagged() {
        XCTAssertFalse(CorpusStore.holdsLegacyArchive())
    }

    /// The guard has to stop the write, not merely report it — detecting the
    /// old layout and then saving over it would lose exactly what it detected.
    func testNothingIsWrittenWhileTheArchiveIsUnmigrated() throws {
        try writeLegacyNote(sidecar: true)
        CorpusStore.refreshLegacyGuard()
        let before = try FileManager.default
            .contentsOfDirectory(atPath: root.path).sorted()

        XCTAssertNil(CorpusStore.save(newNote()), "a refused save reports it, rather than pretending")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
            before,
            "not one file may appear in an archive that has not been migrated"
        )
    }

    /// Pointing at a different archive drops the previous verdict — otherwise
    /// choosing a fresh folder would stay stuck read-only.
    func testChoosingAnotherArchiveClearsTheVerdict() throws {
        try writeLegacyNote(sidecar: true)
        XCTAssertTrue(CorpusStore.refreshLegacyGuard())
        XCTAssertNil(CorpusStore.save(newNote()))

        let fresh = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeFresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fresh) }
        CorpusStore.rootOverride = fresh

        XCTAssertFalse(CorpusStore.refreshLegacyGuard())
        XCTAssertNotNil(CorpusStore.save(newNote()))
    }
}
