import Foundation
@testable import CueMe

/// Additional round-trip fixtures for `NoteDocumentReader`, alongside `RichNote`
/// (the golden-backed fixture). Each covers a shape the golden does not:
/// a minimal note with no session collections at all, a note whose free text
/// is heavy with Unicode/RTL/emoji, and a note whose body contains a literal
/// marker-looking line that must survive the escape rule (design.md §4.12)
/// rather than be mistaken for a real section marker on the next read.
enum NoteReaderFixtures {
    static var minimalNote: MemoryNote {
        MemoryNote(
            id: fixtureUUID("33333333-3333-4333-8333-333333333333"),
            startedAt: fixtureDate("2026-08-08T09:00:00.000Z"),
            endedAt: fixtureDate("2026-08-08T09:00:00.000Z"),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: "Ideia solta sobre horários",
            noteKind: .note,
            markdownBody: "Só um pensamento sobre horários de reunião.",
            labels: ["pessoal"],
            titleSource: .user,
            modifiedAt: fixtureDate("2026-08-08T09:00:00.000Z")
        )
    }

    static var unicodeNote: MemoryNote {
        MemoryNote(
            id: fixtureUUID("44444444-4444-4444-8444-444444444444"),
            startedAt: fixtureDate("2026-08-08T10:00:00.000Z"),
            endedAt: fixtureDate("2026-08-08T10:00:00.000Z"),
            mode: .recording,
            training: false,
            conversationLang: "ar-SA",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: "café · 日本語 · مرحبا 🎉",
            noteKind: .note,
            markdownBody: "مرحبا بالعالم 🌍\nこんにちは世界 🎌\nÀ direita para a esquerda: שלום עולם",
            labels: ["日本語", "emoji-🎉"],
            titleSource: .user,
            modifiedAt: fixtureDate("2026-08-08T10:00:00.000Z")
        )
    }

    static var noteWithLiteralMarkerInBody: MemoryNote {
        MemoryNote(
            id: fixtureUUID("55555555-5555-4555-8555-555555555555"),
            startedAt: fixtureDate("2026-08-08T11:00:00.000Z"),
            endedAt: fixtureDate("2026-08-08T11:00:00.000Z"),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            origin: .written,
            displayTitle: "Exemplo de marcador literal",
            noteKind: .note,
            markdownBody: "Cole aqui o exemplo:\n<!-- cueme:minutes -->\nfim do exemplo.",
            labels: [],
            titleSource: .user,
            modifiedAt: fixtureDate("2026-08-08T11:00:00.000Z")
        )
    }
}
