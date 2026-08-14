import XCTest
@testable import CueMe

final class TranscriptStateTests: XCTestCase {
    private func line(_ text: String, isFinal: Bool = true) -> TranscriptLine {
        .init(speaker: .other, text: text, isFinal: isFinal, ts: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - AC4

    func testNotLoadedReportsTurnCountWithoutLines() {
        let state = TranscriptState.notLoaded(turns: 214)

        XCTAssertEqual(state.turnCount, 214)
        XCTAssertTrue(state.lines.isEmpty)
        XCTAssertFalse(state.isLoaded)
    }

    func testLoadedCountsOnlyFinalTurns() {
        let state = TranscriptState.loaded([line("um"), line("parcial", isFinal: false), line("dois")])

        XCTAssertEqual(state.turnCount, 2)
        XCTAssertEqual(state.lines.count, 3)
        XCTAssertTrue(state.isLoaded)
    }

    // MARK: - AC5

    func testCodableRoundTripsBothCases() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let loaded = TranscriptState.loaded([line("um"), line("dois")])
        let decodedLoaded = try decoder.decode(TranscriptState.self, from: encoder.encode(loaded))
        XCTAssertEqual(decodedLoaded.lines.map(\.text), ["um", "dois"])
        XCTAssertTrue(decodedLoaded.isLoaded)

        let notLoaded = TranscriptState.notLoaded(turns: 7)
        let decodedNotLoaded = try decoder.decode(TranscriptState.self, from: encoder.encode(notLoaded))
        XCTAssertEqual(decodedNotLoaded.turnCount, 7)
        XCTAssertFalse(decodedNotLoaded.isLoaded)
    }

    func testUpdateLineEditsInPlaceWhenLoaded() {
        var state = TranscriptState.loaded([line("mono rapo"), line("outra")])
        let target = try! XCTUnwrap(state.first?.id)

        state.updateLine(id: target) { $0.applyCorrection("monorepo") }

        XCTAssertEqual(state.first?.text, "monorepo")
        XCTAssertEqual(state.first?.originalText, "mono rapo")
        XCTAssertEqual(state.count, 2)
    }

    /// Correcting a line that was never read must not rebuild the state from an
    /// empty array — that would be the erasure this type exists to prevent.
    func testUpdateLineOnNotLoadedIsANoOp() {
        var state = TranscriptState.notLoaded(turns: 214)

        state.updateLine(id: UUID()) { $0.applyCorrection("qualquer coisa") }

        XCTAssertFalse(state.isLoaded)
        XCTAssertEqual(state.turnCount, 214)
    }

    /// The state reads as a collection of its lines so every existing reader
    /// keeps working. Writing is what has to check `isLoaded` — that guard
    /// lives in `TranscriptDocument`, not here.
    func testReadsAsACollectionOfItsLines() {
        let state = TranscriptState.loaded([line("um"), line("dois")])

        XCTAssertEqual(state.count, 2)
        XCTAssertEqual(state.first?.text, "um")
        XCTAssertEqual(state.filter(\.isFinal).count, 2)
        XCTAssertTrue(TranscriptState.notLoaded(turns: 9).isEmpty)
    }
}
