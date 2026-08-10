import XCTest
@testable import CueMe

@MainActor
final class NoteListProjectionTests: XCTestCase {
    private nonisolated(unsafe) var previousArchive: URL?
    private nonisolated(unsafe) var previousInbox: URL?
    private let uiTestArchive = UITestFixtures.uiTestRoot

    override func setUp() {
        super.setUp()
        previousArchive = CorpusStore.rootOverride
        previousInbox = ExternalAudioInbox.rootOverride
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: uiTestArchive)
        CorpusStore.rootOverride = previousArchive
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

    func testAllCountIgnoresSelectedTypeWhileRespectingSectionLabelSearchAndDateScope() {
        let now = Date()
        let written = makeRecord(
            title: "Alpha written",
            startedAt: now.addingTimeInterval(-60),
            origin: .written,
            noteKind: .note,
            folder: "inbox",
            labels: ["focus"]
        )
        let meeting = makeRecord(
            title: "Alpha meeting",
            startedAt: now.addingTimeInterval(-120),
            origin: .live,
            noteKind: .meeting,
            folder: "inbox",
            labels: ["focus"]
        )
        let wrongSearch = makeRecord(
            title: "Beta meeting",
            startedAt: now.addingTimeInterval(-180),
            origin: .live,
            noteKind: .meeting,
            folder: "inbox",
            labels: ["focus"]
        )
        let wrongLabel = makeRecord(
            title: "Alpha other label",
            startedAt: now.addingTimeInterval(-240),
            origin: .written,
            noteKind: .note,
            folder: "inbox",
            labels: ["later"]
        )
        let outsideSection = makeRecord(
            title: "Alpha somewhere else",
            startedAt: now.addingTimeInterval(-300),
            origin: .live,
            noteKind: .meeting,
            folder: "acme",
            labels: ["focus"]
        )
        let tooOld = makeRecord(
            title: "Alpha old",
            startedAt: now.addingTimeInterval(-45 * 86_400),
            origin: .live,
            noteKind: .meeting,
            folder: "inbox",
            labels: ["focus"]
        )
        let app = AppModel(isUITesting: true)
        app.history = [written, meeting, wrongSearch, wrongLabel, outsideSection, tooOld]
        app.selectLibrarySection(.inbox)
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

        // Search ranks the whole corpus; the section still bounds what the
        // column shows. `outsideSection` matches "Alpha" and must stay out.
        app.historySearch = "Alpha"
        let canonicalSearchIDs = app.historySearchResults(typeFilter: .all).map(\.recordID)
        let sectionScopedIDs = canonicalSearchIDs.filter { id in
            app.history.first { $0.id == id }?.relativeFolderPath == "inbox"
        }
        projection = app.noteListProjection
        XCTAssertTrue(canonicalSearchIDs.contains(outsideSection.id))
        XCTAssertEqual(projection.scopedRecords.map(\.id), sectionScopedIDs)
        XCTAssertEqual(projection.count(for: .all), sectionScopedIDs.count)

        app.historyTypeFilter = .meeting
        projection = app.noteListProjection
        XCTAssertEqual(
            projection.visibleRecords.map(\.id),
            sectionScopedIDs.filter { id in
                app.history.first { $0.id == id }?.libraryPresentationKind == .meeting
            }
        )
    }

    func testBuiltInSectionsRemainPartOfScopeBeforeTypeFiltering() {
        let inboxNote = makeRecord(title: "Inbox", origin: .written, noteKind: .note, folder: "inbox")
        let elsewhere = makeRecord(title: "Acme", origin: .live, noteKind: .meeting, folder: "acme")
        let journal = makeRecord(title: "Journal", origin: .written, noteKind: .journal, folder: "inbox")
        // `inbox` is a note like any other, so a sibling whose slug merely
        // starts with the same letters is a different place entirely.
        let lookalike = makeRecord(title: "Inbox antigo", origin: .written, noteKind: .note, folder: "inbox-antigo")
        let nested = makeRecord(title: "Nested", origin: .written, noteKind: .note, folder: "inbox/acme")
        let app = AppModel(isUITesting: true)
        app.history = [inboxNote, elsewhere, journal, lookalike, nested]

        app.selectLibrarySection(.inbox)
        app.historyTypeFilter = .meeting
        var projection = app.noteListProjection
        XCTAssertEqual(
            Set(projection.scopedRecords.map(\.title)),
            ["Inbox", "Journal", "Nested"],
            "the inbox scope is the inbox note and its descendants, nothing else"
        )
        XCTAssertEqual(projection.count(for: .all), 3)
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
        let inboxNote = makeRecord(title: "Inbox note", origin: .written, noteKind: .note, folder: "inbox")
        let inboxMeeting = makeRecord(title: "Inbox meeting", origin: .live, noteKind: .meeting, folder: "inbox")
        let nestedMeeting = makeRecord(
            title: "Nested meeting",
            origin: .live,
            noteKind: .meeting,
            folder: "acme"
        )
        let projection = NoteListProjection(
            history: [inboxNote, inboxMeeting, nestedMeeting],
            searchResults: [
                .init(recordID: nestedMeeting.id, score: 3, snippet: "nested"),
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
        XCTAssertNil(projection.snippet(for: nestedMeeting.id))
    }

    private func makeRecord(
        title: String,
        startedAt: Date = Date(),
        origin: SessionOrigin,
        noteKind: MemoryNoteKind,
        hasAudio: Bool = false,
        attachments: [NoteAttachment] = [],
        folder: String? = nil,
        labels: [String] = []
    ) -> MemoryNote {
        var record = MemoryNote(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            mode: .meeting,
            training: false,
            conversationLang: "en-US",
            nativeLang: "en-US",
            goal: "",
            transcript: [],
            coachCards: [],
            hasAudio: hasAudio,
            origin: origin,
            displayTitle: title,
            noteKind: noteKind,
            labels: labels,
            attachments: attachments
        )
        record.relativeFolderPath = folder
        return record
    }
}
