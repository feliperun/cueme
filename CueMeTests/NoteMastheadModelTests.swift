import XCTest
@testable import CueMe

final class NoteMastheadModelTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_780_000_000)

    private func record(
        origin: SessionOrigin,
        participantNames: [Speaker: String] = [.self: "Você", .other: "Interlocutor"],
        noteKind: MemoryNoteKind? = nil,
        endedAfter: TimeInterval = 0,
        displayTitle: String? = nil
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
            displayTitle: displayTitle,
            noteKind: noteKind
        )
    }

    // MARK: Participants

    func testWrittenNoteNeverFabricatesSpeakersButStillShowsItsLinks() {
        let marina = record(origin: .written, displayTitle: "Marina")
        let written = record(origin: .written, participantNames: [.self: "Felipe", .other: "Sofia"])

        let faces = NoteMastheadModel.participants(for: written, linked: [marina])

        XCTAssertEqual(faces.map(\.name), ["Marina"], "a written note was never in a room")
        XCTAssertEqual(faces.map(\.role), [.linked])
        XCTAssertEqual(faces.first?.noteID, marina.id, "the chip has to know where it navigates")
    }

    /// AC2: the chip is the only affordance that turns a link into navigation,
    /// so it must carry the target id — a name alone cannot be clicked through.
    func testLinkedChipCarriesTheTargetNoteWhileSpeakersDoNot() {
        let marina = record(origin: .written, displayTitle: "Marina")
        let meeting = record(origin: .live, participantNames: [.self: "Felipe", .other: "Sofia"])

        let faces = NoteMastheadModel.participants(for: meeting, linked: [marina])

        XCTAssertEqual(faces.map(\.name), ["Felipe", "Sofia", "Marina"])
        XCTAssertEqual(faces.filter { $0.noteID != nil }.map(\.name), ["Marina"])
        XCTAssertEqual(faces.first { $0.name == "Marina" }?.noteID, marina.id)
    }

    func testMeetingUsesTheNamedParticipants() {
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe Broering", .other: "Sofia Reyes"]
        )

        let participants = NoteMastheadModel.participants(for: meeting, linked: [])

        XCTAssertEqual(participants.map(\.name), ["Felipe Broering", "Sofia Reyes"])
        XCTAssertEqual(participants.map(\.initials), ["FB", "SR"])
        XCTAssertEqual(participants.map(\.role), [.you, .counterpart])
    }

    func testLinkedPeopleAreAppendedAfterTheParticipants() {
        let marcus = record(origin: .written, displayTitle: "Marcus Lund")
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe", .other: "Sofia"],
        )

        let participants = NoteMastheadModel.participants(for: meeting, linked: [marcus])

        XCTAssertEqual(participants.map(\.name), ["Felipe", "Sofia", "Marcus Lund"])
        XCTAssertEqual(participants.last?.role, .linked)
    }

    func testLinkedPersonMatchingAParticipantIsNotDuplicated() {
        let sofia = record(origin: .written, displayTitle: "sofia reyes")
        let meeting = record(
            origin: .live,
            participantNames: [.self: "Felipe", .other: "Sofia Reyes"],
        )

        XCTAssertEqual(
            NoteMastheadModel.participants(for: meeting, linked: [sofia]).map(\.name),
            ["Felipe", "Sofia Reyes"]
        )
    }


    func testBlankParticipantNameIsDropped() {
        let meeting = record(origin: .live, participantNames: [.self: "Felipe", .other: "   "])

        // `participantName(for:)` falls back to the speaker label when unnamed.
        XCTAssertEqual(
            NoteMastheadModel.participants(for: meeting, linked: []).map(\.name),
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
