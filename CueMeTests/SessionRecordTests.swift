import XCTest
@testable import CueMe

final class SessionRecordTests: XCTestCase {

    func testRecordingClockWinsWhenPresent() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let audioStart = sessionStart.addingTimeInterval(12)
        let record = MemoryNote(
            startedAt: sessionStart,
            recordingStartedAt: audioStart,
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
        )
        XCTAssertEqual(record.audioTimelineStart, audioStart)
    }


    func testTranscriptCorrectionPreservesOriginalAndIsCodable() throws {
        var line = TranscriptLine(speaker: .other, text: "mono rapo", isFinal: true)
        line.applyCorrection("monorepo", at: Date(timeIntervalSince1970: 2_000))
        let decoded = try JSONDecoder().decode(
            TranscriptLine.self,
            from: JSONEncoder().encode(line)
        )
        XCTAssertEqual(decoded.text, "monorepo")
        XCTAssertEqual(decoded.originalText, "mono rapo")
        XCTAssertTrue(decoded.wasEdited)
    }
}
