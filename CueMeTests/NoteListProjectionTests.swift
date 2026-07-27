import XCTest
@testable import CueMe

@MainActor
final class NoteListProjectionTests: XCTestCase {
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

    func testVisibleKindAndTabsUseOneClassificationForEveryNoteVariant() {
        let written = makeRecord(title: "Written", origin: .written, noteKind: .note)
        let recordedNote = makeRecord(
            title: "Recorded note",
            origin: .written,
            noteKind: .note,
            hasAudio: true
        )
        let liveNote = makeRecord(title: "Live note", origin: .live, noteKind: .note)
        let journal = makeRecord(title: "Journal", origin: .written, noteKind: .journal)
        let liveJournal = makeRecord(title: "Live journal", origin: .live, noteKind: .journal)
        let liveMeeting = makeRecord(title: "Live", origin: .live, noteKind: .meeting)
        let importedAudio = makeRecord(
            title: "Imported",
            origin: .audioFile,
            noteKind: .importedAudio,
            hasAudio: true
        )
        let attachedRecording = makeRecord(
            title: "Attachment",
            origin: .written,
            noteKind: .recording,
            attachments: [.init(filename: "meeting.m4a", kind: .recording)]
        )
        let custom = makeRecord(title: "Custom", origin: .written, noteKind: .custom)
        let emptyMeeting = makeRecord(title: "Empty meeting", origin: .written, noteKind: .meeting)

        XCTAssertEqual(LibraryFormat.kindTag(written), "NOTE")
        XCTAssertEqual(LibraryFormat.kindTag(recordedNote), "MEETING")
        XCTAssertEqual(LibraryFormat.kindTag(liveNote), "MEETING")
        XCTAssertEqual(LibraryFormat.kindTag(journal), "JOURNAL")
        XCTAssertEqual(LibraryFormat.kindTag(liveJournal), "JOURNAL")
        XCTAssertEqual(LibraryFormat.kindTag(liveMeeting), "MEETING")
        XCTAssertEqual(LibraryFormat.kindTag(importedAudio), "MEETING")
        XCTAssertEqual(LibraryFormat.kindTag(attachedRecording), "MEETING")
        XCTAssertEqual(LibraryFormat.kindTag(custom), "NOTE")
        XCTAssertEqual(LibraryFormat.kindTag(emptyMeeting), "NOTE")

        let records = [
            written, recordedNote, liveNote, journal, liveJournal,
            liveMeeting, importedAudio, attachedRecording, custom, emptyMeeting,
        ]
        XCTAssertEqual(records.filter(HistoryTypeFilter.meeting.matches).map(\.title), [
            "Recorded note", "Live note", "Live", "Imported", "Attachment",
        ])
        // Notes is the visible NOTE complement. Journals stay exclusive to the
        // Journal tree section instead of leaking into the Notes tab.
        XCTAssertEqual(records.filter(HistoryTypeFilter.note.matches).map(\.title), [
            "Written", "Custom", "Empty meeting",
        ])
    }

    func testAllCountIgnoresSelectedTypeWhileRespectingProjectLabelSearchAndDateScope() {
        let projectID = UUID()
        let otherProjectID = UUID()
        let now = Date()
        let written = makeRecord(
            title: "Alpha written",
            startedAt: now.addingTimeInterval(-60),
            origin: .written,
            noteKind: .note,
            projectID: projectID,
            labels: ["focus"]
        )
        let meeting = makeRecord(
            title: "Alpha meeting",
            startedAt: now.addingTimeInterval(-120),
            origin: .live,
            noteKind: .meeting,
            projectID: projectID,
            labels: ["focus"]
        )
        let wrongSearch = makeRecord(
            title: "Beta meeting",
            startedAt: now.addingTimeInterval(-180),
            origin: .live,
            noteKind: .meeting,
            projectID: projectID,
            labels: ["focus"]
        )
        let wrongLabel = makeRecord(
            title: "Alpha other label",
            startedAt: now.addingTimeInterval(-240),
            origin: .written,
            noteKind: .note,
            projectID: projectID,
            labels: ["later"]
        )
        let wrongProject = makeRecord(
            title: "Alpha other project",
            startedAt: now.addingTimeInterval(-300),
            origin: .live,
            noteKind: .meeting,
            projectID: otherProjectID,
            labels: ["focus"]
        )
        let tooOld = makeRecord(
            title: "Alpha old",
            startedAt: now.addingTimeInterval(-45 * 86_400),
            origin: .live,
            noteKind: .meeting,
            projectID: projectID,
            labels: ["focus"]
        )
        let app = AppModel(isUITesting: true)
        app.history = [written, meeting, wrongSearch, wrongLabel, wrongProject, tooOld]
        app.libraryProjectFilterID = projectID
        app.libraryLabelFilter = "focus"
        app.historySearch = ""
        app.historyDateFilter = .last30Days
        app.historyTypeFilter = .meeting

        var projection = app.noteListProjection
        XCTAssertEqual(projection.count(for: .all), 3)
        XCTAssertEqual(projection.count(for: .meeting), 2)
        XCTAssertEqual(projection.count(for: .note), 1)
        XCTAssertEqual(Set(projection.visibleRecords.map(\.id)), Set([meeting.id, wrongSearch.id]))

        app.historyTypeFilter = .note
        projection = app.noteListProjection
        XCTAssertEqual(projection.count(for: .all), 3)
        XCTAssertEqual(projection.visibleRecords.map(\.id), [written.id])

        app.historySearch = "Alpha"
        let canonicalSearchIDs = app.historySearchResults(typeFilter: .all).map(\.recordID)
        projection = app.noteListProjection
        XCTAssertEqual(projection.scopedRecords.map(\.id), canonicalSearchIDs)
        XCTAssertEqual(projection.count(for: .all), canonicalSearchIDs.count)

        app.historyTypeFilter = .meeting
        projection = app.noteListProjection
        XCTAssertEqual(
            projection.visibleRecords.map(\.id),
            canonicalSearchIDs.filter { id in
                app.history.first { $0.id == id }?.libraryPresentationKind == .meeting
            }
        )
    }

    func testBuiltInSectionsRemainPartOfScopeBeforeTypeFiltering() {
        let inboxNote = makeRecord(title: "Inbox", origin: .written, noteKind: .note)
        let projectMeeting = makeRecord(
            title: "Project",
            origin: .live,
            noteKind: .meeting,
            projectID: UUID()
        )
        let journal = makeRecord(title: "Journal", origin: .written, noteKind: .journal)
        let app = AppModel(isUITesting: true)
        app.history = [inboxNote, projectMeeting, journal]

        app.selectLibrarySection(.inbox)
        app.historyTypeFilter = .meeting
        var projection = app.noteListProjection
        XCTAssertEqual(projection.count(for: .all), 2)
        XCTAssertTrue(projection.visibleRecords.isEmpty)

        app.selectLibrarySection(.journal)
        XCTAssertEqual(app.historyTypeFilter, .all)
        projection = app.noteListProjection
        XCTAssertEqual(projection.count(for: .all), 1)
        XCTAssertEqual(projection.visibleRecords.map(\.id), [journal.id])
        XCTAssertEqual(projection.count(for: .note), 0)
        XCTAssertEqual(projection.count(for: .meeting), 0)
    }

    func testProjectionCarriesOneScopedResultSetCountsSelectionAndSnippets() {
        let inboxNote = makeRecord(title: "Inbox note", origin: .written, noteKind: .note)
        let inboxMeeting = makeRecord(title: "Inbox meeting", origin: .live, noteKind: .meeting)
        let projectMeeting = makeRecord(
            title: "Project meeting",
            origin: .live,
            noteKind: .meeting,
            projectID: UUID()
        )
        let projection = NoteListProjection(
            history: [inboxNote, inboxMeeting, projectMeeting],
            searchResults: [
                .init(recordID: projectMeeting.id, score: 3, snippet: "project"),
                .init(recordID: inboxMeeting.id, score: 2, snippet: "meeting"),
                .init(recordID: inboxNote.id, score: 1, snippet: "note"),
            ],
            section: .inbox,
            selectedType: .meeting
        )

        XCTAssertEqual(projection.scopedRecords.map(\.id), [inboxMeeting.id, inboxNote.id])
        XCTAssertEqual(projection.visibleRecords.map(\.id), [inboxMeeting.id])
        XCTAssertEqual(projection.count(for: .all), 2)
        XCTAssertEqual(projection.count(for: .meeting), 1)
        XCTAssertEqual(projection.count(for: .note), 1)
        XCTAssertEqual(projection.snippet(for: inboxMeeting.id), "meeting")
        XCTAssertEqual(projection.snippet(for: inboxNote.id), "note")
        XCTAssertNil(projection.snippet(for: projectMeeting.id))
    }

    private func makeRecord(
        title: String,
        startedAt: Date = Date(),
        origin: SessionOrigin,
        noteKind: MemoryNoteKind,
        hasAudio: Bool = false,
        attachments: [NoteAttachment] = [],
        projectID: UUID? = nil,
        labels: [String] = []
    ) -> SessionRecord {
        SessionRecord(
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
            hasAudio: hasAudio,
            origin: origin,
            displayTitle: title,
            projectID: projectID,
            noteKind: noteKind,
            labels: labels,
            attachments: attachments
        )
    }
}
