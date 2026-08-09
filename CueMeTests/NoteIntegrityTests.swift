import XCTest
@testable import CueMe

/// AC1 — saving a note persists only the two integrity counters, never a
/// per-event log. `MemoryNote.diagnostics` was deleted for exactly this reason
/// (see ADR 0045); this test proves the replacement field keeps the promise.
final class NoteIntegrityTests: XCTestCase {
    func testSavedNoteKeepsOnlyIntegrityCounters() throws {
        var record = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )
        record.integrity = NoteIntegrity(recoveries: 2, errors: 1)

        let encoded = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(object["diagnostics"], "the durable note must not carry a diagnostics field anymore")

        let integrity = try XCTUnwrap(object["integrity"] as? [String: Any])
        XCTAssertEqual(Set(integrity.keys), ["recoveries", "errors"])
        XCTAssertEqual(integrity["recoveries"] as? Int, 2)
        XCTAssertEqual(integrity["errors"] as? Int, 1)
    }
}
