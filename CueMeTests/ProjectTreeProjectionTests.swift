import XCTest
@testable import CueMe

@MainActor
final class ProjectTreeProjectionTests: XCTestCase {
    private nonisolated(unsafe) var previousArchive: URL?
    private nonisolated(unsafe) var previousInbox: URL?
    private let uiTestArchive = FileManager.default.temporaryDirectory
        .appendingPathComponent("CueMeUITests-archive", isDirectory: true)

    override func setUp() {
        super.setUp()
        previousArchive = SessionStore.rootOverride
        previousInbox = ExternalAudioInbox.rootOverride
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: uiTestArchive)
        SessionStore.rootOverride = previousArchive
        ExternalAudioInbox.rootOverride = previousInbox
        previousArchive = nil
        previousInbox = nil
        super.tearDown()
    }

    func testProjectRecordsIgnoreLibraryFiltersAndSortNewestFirst() {
        let projectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let otherProjectID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let older = makeRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1_000),
            projectID: projectID
        )
        let other = makeRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            startedAt: Date(timeIntervalSince1970: 2_000),
            projectID: otherProjectID
        )
        let newer = makeRecord(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            startedAt: Date(timeIntervalSince1970: 3_000),
            projectID: projectID
        )
        let app = AppModel(isUITesting: true)
        app.history = [older, other, newer]
        app.libraryProjectFilterID = projectID
        app.historySearch = "zzzz"
        app.historyTypeFilter = .all

        XCTAssertTrue(app.noteListProjection.visibleRecords.isEmpty)
        XCTAssertEqual(app.projectTreeRecords(for: projectID).map(\.id), [newer.id, older.id])
    }

    func testSelectedProjectAndSelectedRecordProjectAreAlwaysExpanded() {
        let projectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let record = makeRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1_000),
            projectID: projectID
        )
        let app = AppModel(isUITesting: true)
        app.history = [record]

        app.libraryProjectFilterID = projectID
        XCTAssertTrue(app.isProjectForcedExpanded(projectID))
        XCTAssertTrue(app.isProjectExpanded(projectID, explicitly: []))

        app.libraryProjectFilterID = nil
        app.selectedSessionID = record.id
        XCTAssertTrue(app.isProjectForcedExpanded(projectID))
        XCTAssertTrue(app.isProjectExpanded(projectID, explicitly: []))
        XCTAssertFalse(app.isProjectForcedExpanded(UUID()))
        XCTAssertFalse(app.isProjectExpanded(UUID(), explicitly: []))
    }

    func testExplicitExpansionCanCollapseWhenProjectIsNotForcedOpen() {
        let projectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let app = AppModel(isUITesting: true)

        XCTAssertFalse(app.isProjectForcedExpanded(projectID))
        XCTAssertFalse(app.isProjectExpanded(projectID, explicitly: []))
        XCTAssertTrue(app.isProjectExpanded(projectID, explicitly: [projectID]))
        XCTAssertFalse(app.isProjectExpanded(projectID, explicitly: []))
    }

    func testSelectingTreeRecordKeepsProjectAndNoteColumnsConsistent() {
        let projectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let record = makeRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1_000),
            projectID: projectID
        )
        let app = AppModel(isUITesting: true)
        app.history = [record]
        app.historyTypeFilter = .meeting
        app.historyDateFilter = .today
        app.historySearch = "does not match"
        app.libraryLabelFilter = "hidden"
        app.librarySection = .journal

        app.selectProjectTreeRecord(record)

        XCTAssertEqual(app.libraryProjectFilterID, projectID)
        XCTAssertEqual(app.activeProjectID, projectID)
        XCTAssertEqual(app.selectedSessionID, record.id)
        XCTAssertEqual(app.librarySection, .all)
        XCTAssertEqual(app.historyTypeFilter, .all)
        XCTAssertEqual(app.historyDateFilter, .all)
        XCTAssertEqual(app.historySearch, "")
        XCTAssertNil(app.libraryLabelFilter)
        XCTAssertEqual(app.noteListProjection.visibleRecords.map(\.id), [record.id])
    }

    func testLiveChildOnlyBelongsToTheActiveProjectWhileRunning() {
        let activeProjectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

        XCTAssertTrue(ProjectTreeProjection.showsLiveChild(
            for: activeProjectID,
            activeProjectID: activeProjectID,
            isRunning: true
        ))
        XCTAssertFalse(ProjectTreeProjection.showsLiveChild(
            for: UUID(),
            activeProjectID: activeProjectID,
            isRunning: true
        ))
        XCTAssertFalse(ProjectTreeProjection.showsLiveChild(
            for: activeProjectID,
            activeProjectID: activeProjectID,
            isRunning: false
        ))
        XCTAssertFalse(ProjectTreeProjection.showsLiveChild(
            for: activeProjectID,
            activeProjectID: nil,
            isRunning: true
        ))
    }

    func testUITestAppCreatesSemanticIndexInsideItsIsolatedArchive() {
        let app = AppModel(isUITesting: true)

        XCTAssertEqual(SessionStore.rootOverride?.standardizedFileURL, uiTestArchive.standardizedFileURL)
        XCTAssertTrue(
            app.semanticMemoryIndexURLForTesting.standardizedFileURL.path
                .hasPrefix(uiTestArchive.standardizedFileURL.path + "/")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.semanticMemoryIndexURLForTesting.path))
    }

    func testPastNotesSearchUsesTheInjectedIsolatedSemanticIndex() {
        let app = AppModel(isUITesting: true)
        let fixtureRecordID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let fixtureProjectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        app.activeProjectID = fixtureProjectID

        let results = app.searchPastNotes("carro sustentável")

        XCTAssertTrue(results.contains { $0.recordID == fixtureRecordID })
        XCTAssertTrue(app.semanticMemoryIndexedSessionIDsForTesting.contains(fixtureRecordID))
        XCTAssertTrue(
            app.semanticMemoryIndexURLForTesting.standardizedFileURL.path
                .hasPrefix(uiTestArchive.standardizedFileURL.path + "/")
        )
    }

    private func makeRecord(id: UUID, startedAt: Date, projectID: UUID) -> SessionRecord {
        SessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            mode: .meeting,
            training: false,
            conversationLang: "en-US",
            nativeLang: "en-US",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            projectID: projectID
        )
    }
}
