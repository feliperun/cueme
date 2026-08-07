import XCTest
@testable import CueMe

@MainActor
final class CoachCardNavigationTests: XCTestCase {
    /// The live pane is a hero card: falling behind on the newest cue is the same
    /// as showing the wrong answer, so a fresh card always takes the stage.
    func testNewestCardBecomesActive() {
        let app = AppModel()
        let first = card(guide: "Primeira")
        let second = card(guide: "Segunda")
        let third = card(guide: "Terceira")

        app.upsertCoach(first)
        app.upsertCoach(second)
        app.upsertCoach(third)

        XCTAssertEqual(app.activeCoachCard?.id, third.id)
        XCTAssertEqual(app.activeCoachPosition?.index, 3)
        XCTAssertEqual(app.activeCoachPosition?.count, 3)
    }

    /// Pinning is the only way to hold a cue on screen; everything else advances.
    func testPinnedCardHoldsTheStageAndCountsWhatIsWaiting() {
        let app = AppModel()
        let pinned = card(guide: "Fixada")
        app.upsertCoach(pinned)
        app.toggleActiveCoachPin()

        app.upsertCoach(card(guide: "Depois"))
        app.upsertCoach(card(guide: "Mais depois"))

        XCTAssertEqual(app.activeCoachCard?.id, pinned.id)
        XCTAssertTrue(app.isActiveCoachPinned)
        XCTAssertEqual(app.pendingCoachCount, 2)
    }

    /// Streaming updates of the pinned card itself must still land.
    func testPinnedCardStillReceivesItsOwnUpdates() {
        let app = AppModel()
        let id = UUID()
        app.upsertCoach(card(id: id, guide: "Parcial"))
        app.toggleActiveCoachPin()

        app.upsertCoach(card(id: id, guide: "Parcial", say: "Frase final", streaming: false))

        XCTAssertEqual(app.activeCoachCard?.id, id)
        XCTAssertEqual(app.activeCoachCard?.sayNative, "Frase final")
    }

    /// A cue that resolves to `NADA` is pruned. The pane must fall back to the
    /// last useful card instead of flipping to the empty state mid-session.
    func testPruningActiveCardFallsBackToPreviousUsefulCard() {
        let app = AppModel()
        let kept = card(guide: "Vale")
        let emptied = UUID()
        app.upsertCoach(kept)
        app.upsertCoach(card(id: emptied, guide: "Some"))
        app.upsertCoach(card(id: emptied, guide: "", streaming: false))

        app.pruneEmptyCoachCards()

        XCTAssertEqual(app.activeCoachCard?.id, kept.id)
    }

    func testPruningLeavesNoActiveCardWhenNothingSurvives() {
        let app = AppModel()
        let only = UUID()
        app.upsertCoach(card(id: only, guide: "Some"))
        app.upsertCoach(card(id: only, guide: "", streaming: false))

        app.pruneEmptyCoachCards()

        XCTAssertNil(app.activeCoachCard)
    }

    /// The local instant cue is a placeholder, not an answer.
    func testOnlyModelAnswersCountAsAnsweredCue() {
        XCTAssertFalse(SessionCoordinator.carriesModelAnswer(card(guide: "⭐ STAR")))
        XCTAssertTrue(SessionCoordinator.carriesModelAnswer(card(guide: "⭐ STAR", say: "Diga isso")))
        XCTAssertTrue(
            SessionCoordinator.carriesModelAnswer(
                CoachCard(guidePT: "", sayConversation: "Say this", sayNative: "")
            )
        )
    }

    private func card(
        id: UUID = UUID(),
        guide: String,
        say: String = "",
        streaming: Bool = true
    ) -> CoachCard {
        CoachCard(id: id, guidePT: guide, sayNative: say, isStreaming: streaming)
    }
}
