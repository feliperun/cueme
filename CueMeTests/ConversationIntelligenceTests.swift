import XCTest
@testable import CueMe

final class ConversationIntelligenceTests: XCTestCase {
    func testDetectorDistinguishesTechnicalAndOneOnOneMeetings() {
        let technical = [
            Turn(speaker: .other, text: "Qual arquitetura suporta esse volume?"),
            Turn(speaker: .self, text: "Precisamos avaliar latência, rollback e observabilidade."),
            Turn(speaker: .other, text: "Quais são os trade-offs dessa API?")
        ]
        let oneOnOne = [
            Turn(speaker: .other, text: "Quero conversar sobre seu feedback e crescimento."),
            Turn(speaker: .self, text: "Minha expectativa de carreira é assumir mais responsabilidade."),
            Turn(speaker: .other, text: "Como posso apoiar seu desenvolvimento no time?")
        ]

        XCTAssertEqual(ConversationStyleDetector.detect(turns: technical, fallback: .meeting), .technical)
        XCTAssertEqual(ConversationStyleDetector.detect(turns: oneOnOne, fallback: .meeting), .oneOnOne)
    }

    func testExplicitInterviewAndSalesModesRemainStrongSignals() {
        XCTAssertEqual(ConversationStyleDetector.detect(turns: [], fallback: .interview), .interview)
        XCTAssertEqual(ConversationStyleDetector.detect(turns: [], fallback: .sales), .sales)
    }

    func testCoachOpportunityRejectsGenericSpeechAndAcceptsHighValueMoment() {
        XCTAssertFalse(CoachOpportunity.evaluate(
            text: "Aqui está a atualização semanal do projeto.",
            style: .openMeeting
        ).isHighConfidence)
        let opportunity = CoachOpportunity.evaluate(
            text: "Então ficou decidido, mas quem é o responsável e qual é o prazo?",
            style: .openMeeting
        )
        XCTAssertTrue(opportunity.isHighConfidence)
        XCTAssertEqual(opportunity.kind, .ownership)
    }

    func testInterviewQuestionsRemainActionableWithoutSTTPunctuation() {
        let opportunity = CoachOpportunity.evaluate(
            text: "Walk me through a difficult migration you led",
            style: .interview
        )
        XCTAssertEqual(opportunity.kind, .question)
        XCTAssertTrue(opportunity.isHighConfidence)
    }
}

@MainActor
final class CoachPresentationPolicyTests: XCTestCase {
    func testNewCoachCardWaitsUntilUserReplacesCurrentSuggestion() {
        let app = AppModel()
        let first = CoachCard(guidePT: "Primeira", sayNative: "Primeira resposta", isStreaming: false)
        let second = CoachCard(guidePT: "Segunda", sayNative: "Segunda resposta", isStreaming: false)

        app.upsertCoach(first)
        app.upsertCoach(second)

        XCTAssertEqual(app.activeCoachCard?.id, first.id)
        XCTAssertEqual(app.pendingCoachCount, 1)
        app.toggleActiveCoachPin()
        XCTAssertTrue(app.isActiveCoachPinned)
        app.useActiveCoach()
        XCTAssertEqual(app.coachFeedback[first.id], .helpful)
        XCTAssertEqual(app.activeCoachCard?.id, second.id)
    }

    func testUsingCurrentCardAdvancesPendingSuggestionsInArrivalOrder() {
        let app = AppModel()
        let cards = (1...3).map {
            CoachCard(guidePT: "Dica \($0)", sayNative: "Resposta \($0)")
        }
        cards.forEach(app.upsertCoach)

        XCTAssertEqual(app.activeCoachCard?.id, cards[0].id)
        app.useActiveCoach()
        XCTAssertEqual(app.activeCoachCard?.id, cards[1].id)
        app.useActiveCoach()
        XCTAssertEqual(app.activeCoachCard?.id, cards[2].id)
    }
}
