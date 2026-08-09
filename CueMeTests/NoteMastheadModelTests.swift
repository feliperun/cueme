import XCTest
@testable import CueMe

final class NoteMastheadModelTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_780_000_000)

    private func record(
        origin: SessionOrigin,
        participantNames: [Speaker: String] = [.self: "Você", .other: "Interlocutor"],
        personIDs: [UUID] = [],
        noteKind: MemoryNoteKind? = nil,
        endedAfter: TimeInterval = 0
    ) -> MemoryNote {
        MemoryNote(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(endedAfter),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            participantNames: participantNames,
            origin: origin,
            personIDs: personIDs,
            noteKind: noteKind
        )
    }

    // MARK: Participants

    func testWrittenNoteNeverFabricatesParticipants() {
        let people = [KnowledgePerson(name: "Marina")]
        let written = record(origin: .written, personIDs: people.map(\.id))

        XCTAssertTrue(NoteMastheadModel.participants(for: written, people: people).isEmpty)
    }

    func testMeetingUsesTheNamedParticipants() {
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe Broering", .other: "Sofia Reyes"]
        )

        let participants = NoteMastheadModel.participants(for: meeting, people: [])

        XCTAssertEqual(participants.map(\.name), ["Felipe Broering", "Sofia Reyes"])
        XCTAssertEqual(participants.map(\.initials), ["FB", "SR"])
        XCTAssertEqual(participants.map(\.role), [.you, .counterpart])
    }

    func testLinkedPeopleAreAppendedAfterTheParticipants() {
        let marcus = KnowledgePerson(name: "Marcus Lund")
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe", .other: "Sofia"],
            personIDs: [marcus.id]
        )

        let participants = NoteMastheadModel.participants(for: meeting, people: [marcus])

        XCTAssertEqual(participants.map(\.name), ["Felipe", "Sofia", "Marcus Lund"])
        XCTAssertEqual(participants.last?.role, .linked)
    }

    func testLinkedPersonMatchingAParticipantIsNotDuplicated() {
        let sofia = KnowledgePerson(name: "sofia reyes")
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe", .other: "Sofia Reyes"],
            personIDs: [sofia.id]
        )

        XCTAssertEqual(
            NoteMastheadModel.participants(for: meeting, people: [sofia]).map(\.name),
            ["Felipe", "Sofia Reyes"]
        )
    }

    func testUnlinkedPeopleAreIgnored() {
        let stranger = KnowledgePerson(name: "Stranger")
        let meeting = record(origin: .live, participantNames: [.self: "Felipe", .other: "Sofia"])

        XCTAssertEqual(
            NoteMastheadModel.participants(for: meeting, people: [stranger]).map(\.name),
            ["Felipe", "Sofia"]
        )
    }

    func testBlankParticipantNameIsDropped() {
        let meeting = record(origin: .live, participantNames: [.self: "Felipe", .other: "   "])

        // `participantName(for:)` falls back to the speaker label when unnamed.
        XCTAssertEqual(
            NoteMastheadModel.participants(for: meeting, people: []).map(\.name),
            ["Felipe", "Interlocutor"]
        )
    }

    // MARK: Initials

    func testInitialsUseAtMostTwoWords() {
        XCTAssertEqual(NoteMastheadModel.initials(for: "Felipe Ribeiro Broering"), "FR")
        XCTAssertEqual(NoteMastheadModel.initials(for: "sofia"), "S")
        XCTAssertEqual(NoteMastheadModel.initials(for: "   "), "?")
    }

    // MARK: Eyebrow

    func testEyebrowCombinesDateAndKind() {
        let written = record(origin: .written, noteKind: .note)

        XCTAssertEqual(
            NoteMastheadModel.eyebrow(for: written, dateText: "jul 23, 2026"),
            "JUL 23, 2026 · NOTA"
        )
    }

    func testEyebrowAddsDurationOnlyForCapturedNotes() {
        let meeting = record(origin: .live, noteKind: .meeting, endedAfter: 1_471)

        XCTAssertEqual(
            NoteMastheadModel.eyebrow(for: meeting, dateText: "jul 23, 2026"),
            "JUL 23, 2026 · REUNIÃO · 24:31"
        )
    }

    func testEyebrowOmitsZeroDuration() {
        let meeting = record(origin: .live, noteKind: .meeting, endedAfter: 0)

        XCTAssertEqual(
            NoteMastheadModel.eyebrow(for: meeting, dateText: "jul 23, 2026"),
            "JUL 23, 2026 · REUNIÃO"
        )
    }
}
