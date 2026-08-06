import XCTest
@testable import CueMe

final class TranscriptBusTests: XCTestCase {
    func testSubscriberRetainsEveryFinalDuringConsumerStall() async {
        let bus = TranscriptBus(maxTurns: 1_500)
        let stream = await bus.subscribe()

        for index in 0..<1_000 {
            await bus.publish(.init(
                speaker: .other,
                text: "Final \(index)",
                isFinal: true,
                isEndOfTurn: true
            ))
        }
        await bus.finish()

        var received: [TranscriptEvent] = []
        for await event in stream { received.append(event) }
        XCTAssertEqual(received.count, 1_000)
        XCTAssertEqual(received.last?.text, "Final 999")
    }

    func testRemovesTurnLaterConfirmedAsEcho() async {
        let bus = TranscriptBus()
        let echoed = TranscriptEvent(
            speaker: .self,
            text: "Ainda a expectativa",
            isFinal: true,
            isEndOfTurn: true
        )

        await bus.publish(echoed)
        await bus.removeTurn(id: echoed.id)

        let window = await bus.window()
        XCTAssertTrue(window.isEmpty)
    }

    func testReturnsOnlyTurnsAddedSinceSummaryCursorAndAllowsCorrection() async {
        let bus = TranscriptBus()
        let first = TranscriptEvent(speaker: .other, text: "Mono rapo", isFinal: true, isEndOfTurn: true)
        await bus.publish(first)
        let initial = await bus.turns(since: 0)
        XCTAssertEqual(initial.turns.map(\.text), ["Mono rapo"])
        XCTAssertEqual(initial.cursor, 1)

        await bus.updateTurn(id: first.id, text: "monorepo")
        let corrected = await bus.window()
        XCTAssertEqual(corrected.first?.text, "monorepo")

        await bus.publish(.init(speaker: .self, text: "Entendi", isFinal: true, isEndOfTurn: true))
        let delta = await bus.turns(since: initial.cursor)
        XCTAssertEqual(delta.turns.map(\.text), ["Entendi"])
        XCTAssertEqual(delta.cursor, 2)
    }
}
