import Foundation
@testable import CueMe

/// Free functions rather than members of `RichNote`: a `static let` whose
/// initialiser calls a `static func` on the same type makes the Swift 6 type
/// checker report a circular reference.
func fixtureUUID(_ value: String) -> UUID { UUID(uuidString: value)! }

extension ISO8601DateFormatter {
    static var okfFixture: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

func fixtureDate(_ value: String) -> Date { ISO8601DateFormatter.okfFixture.date(from: value)! }

/// The note behind `specs/okf-corpus/contracts/note.md`. Every id and date here
/// is pinned to the golden file — change one and the contract test fails, which
/// is the point.
enum RichNote {
    static let noteID: UUID = UUID(uuidString: "1a2b3c4d-0000-4000-8000-000000000001")!
    static let turn1ID: UUID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!
    static let turn2ID: UUID = UUID(uuidString: "70000000-0000-4000-8000-000000000002")!
    static let evidenceID: UUID = UUID(uuidString: "e0000000-0000-4000-8000-000000000001")!
    static let coachCardID: UUID = UUID(uuidString: "c1000000-0000-4000-8000-000000000001")!

    static let startedAt: Date = ISO8601DateFormatter.okfFixture.date(from: "2026-08-08T14:30:11.000Z")!
    static let modifiedAt: Date = ISO8601DateFormatter.okfFixture.date(from: "2026-08-08T15:12:44.318Z")!

    static var note: MemoryNote {
        var value = MemoryNote(
            id: noteID,
            startedAt: startedAt,
            recordingStartedAt: startedAt,
            endedAt: fixtureDate("2026-08-08T15:00:11.000Z"),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "Definir a estratégia de mobilidade da diretoria",
            transcript: [
                TranscriptLine(
                    id: turn1ID, speaker: .other,
                    text: "O veículo elétrico será adotado no próximo trimestre.",
                    isFinal: true, ts: fixtureDate("2026-08-08T14:30:53.000Z")
                ),
                TranscriptLine(
                    id: turn2ID, speaker: .self,
                    text: "Vamos entregar no monorepo na sexta-feira.",
                    translation: "We will deliver on the monorepo on Friday.",
                    isFinal: true, ts: fixtureDate("2026-08-08T14:31:02.000Z"),
                    sourceTurnID: fixtureUUID("70000000-0000-4000-8000-0000000000ff"),
                    originalText: "Vamos entregar no mono rapo na sexta.",
                    editedAt: fixtureDate("2026-08-08T15:04:10.000Z")
                )
            ],
            coachCards: [
                CoachCard(
                    id: coachCardID,
                    guidePT: "Responda com MOTIVO → EVIDÊNCIA → IMPACTO. Ancore no custo por km.",
                    sayConversation: "We can pilot ten vehicles next quarter and measure cost per km.",
                    sayNative: "Podemos pilotar dez veículos no próximo trimestre e medir o custo por km.",
                    keytermsConversation: ["fleet", "TCO"],
                    kind: .answer, severity: .info, isStreaming: false,
                    ts: fixtureDate("2026-08-08T14:30:58.000Z")
                )
            ],
            minutes: MeetingMinutes(
                overview: "A equipe aprovou a migração da frota.",
                topics: [
                    MeetingTopic(
                        id: fixtureUUID("c0000000-0000-4000-8000-000000000001"),
                        title: "Mobilidade",
                        summary: "Troca gradual da frota por veículos elétricos, começando pela regional sul.",
                        updatedAt: fixtureDate("2026-08-08T14:58:00.000Z")
                    )
                ]
            ),
            participantNames: [.self: "Felipe", .other: "Marina"],
            coachModel: .opus,
            summaryModel: .sonnet,
            vocabulary: CustomVocabulary(keyterms: ["monorepo"], replacements: ["mono rapo": "monorepo"]),
            hasAudio: true,
            audioDuration: 1785.4,
            integrity: NoteIntegrity(recoveries: 1, errors: 0),
            coachFeedback: [coachCardID: .helpful],
            notes: [
                SessionNote(
                    id: fixtureUUID("b0000000-0000-4000-8000-000000000001"),
                    timeOffset: 50,
                    text: "Orçamento reservado para carregadores",
                    createdAt: fixtureDate("2026-08-08T14:31:01.000Z")
                )
            ],
            takeaways: [
                SessionTakeaway(
                    id: fixtureUUID("a0000000-0000-4000-8000-000000000001"),
                    text: "Solicitar propostas aos fornecedores",
                    isDone: false,
                    createdAt: fixtureDate("2026-08-08T15:01:00.000Z"),
                    evidence: [evidence],
                    confidence: 0.94,
                    assignee: "Marina",
                    dueAt: fixtureDate("2026-08-15T00:00:00.000Z")
                ),
                SessionTakeaway(
                    id: fixtureUUID("a0000000-0000-4000-8000-000000000002"),
                    text: "Reservar orçamento para carregadores",
                    isDone: true,
                    createdAt: fixtureDate("2026-08-08T15:01:02.000Z")
                )
            ],
            origin: .live,
            displayTitle: "Estratégia de frota elétrica",
            review: MeetingReview(
                decisions: [
                    MeetingReviewItem(
                        id: fixtureUUID("d0000000-0000-4000-8000-000000000001"),
                        text: "Adotar veículos elétricos no próximo trimestre",
                        evidence: [evidence],
                        confidence: 0.97
                    )
                ],
                openQuestions: [
                    MeetingReviewItem(
                        id: fixtureUUID("d0000000-0000-4000-8000-000000000002"),
                        text: "Qual fornecedor terá melhor cobertura na regional sul?",
                        supersedesID: fixtureUUID("d0000000-0000-4000-8000-0000000000ff")
                    )
                ],
                followUp: "Enviar a ata no Slack até amanhã de manhã."
            ),
            artifacts: [
                SessionArtifact(
                    id: fixtureUUID("f0000000-0000-4000-8000-000000000001"),
                    kind: .answer,
                    title: "Follow-up",
                    body: "Oi Marina, seguem os pontos do nosso alinhamento sobre a frota.",
                    createdAt: fixtureDate("2026-08-08T15:10:00.000Z")
                )
            ],
            links: ["/pessoas/marina-souza.md"],
            noteKind: .meeting,
            markdownBody: """
            A diretoria pediu um plano em duas semanas. Minha leitura é que o gargalo
            não é o veículo, é a instalação dos carregadores.
            """,
            labels: ["frota", "mobilidade"],
            attachments: [
                NoteAttachment(
                    id: fixtureUUID("90000000-0000-4000-8000-000000000001"),
                    filename: "raw/attachments/proposta-fornecedor.pdf",
                    kind: .document,
                    addedAt: fixtureDate("2026-08-08T14:52:03.000Z")
                )
            ],
            titleSource: .user,
            modifiedAt: modifiedAt
        )
        value.relativeFolderPath = nil
        return value
    }

    static let evidence: MemoryEvidence = MemoryEvidence(
        id: evidenceID,
        turnID: turn1ID,
        timestamp: 42,
        quote: "O veículo elétrico será adotado no próximo trimestre."
    )

}
