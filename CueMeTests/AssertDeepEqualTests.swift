import XCTest
@testable import CueMe

/// `assertDeepEqual` exists because `MemoryNote` conforms to `Equatable` by `id`
/// alone. Every round-trip test in this plan depends on it actually comparing
/// fields, so it gets its own tests.
final class AssertDeepEqualTests: XCTestCase {
    private func note(title: String = "Original") -> MemoryNote {
        MemoryNote(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            displayTitle: title
        )
    }

    // MARK: - AC1

    func testFailsNamingTheDivergentField() {
        var other = note()
        other.markdownBody = "diferente"

        let failures = deepEqualFailures(note(), other)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.field, "markdownBody")
    }

    func testReportsEveryDivergentField() {
        var other = note(title: "Outro")
        other.goal = "outro objetivo"
        other.labels = ["x"]

        let fields = Set(deepEqualFailures(note(), other).map(\.field))

        XCTAssertEqual(fields, ["displayTitle", "goal", "labels"])
    }

    func testIdenticalNotesHaveNoFailures() {
        XCTAssertTrue(deepEqualFailures(note(), note()).isEmpty)
    }

    // MARK: - AC2

    func testFailsWhenTheModelGainsAField() {
        XCTAssertEqual(
            Mirror(reflecting: note()).children.count,
            MemoryNoteFieldCount.pinned,
            """
            MemoryNote gained or lost a stored field. Update assertDeepEqual to \
            compare it, then update MemoryNoteFieldCount.pinned. Skipping this \
            is how a field silently stops round-tripping.
            """
        )
    }

    // MARK: - AC3

    func testEqualByIdIsNotDeepEqual() {
        var other = note()
        other.markdownBody = "totalmente diferente"
        other.labels = ["nada", "a", "ver"]

        // This is the trap the helper exists to close: XCTAssertEqual passes,
        // because MemoryNote's == compares only `id`.
        XCTAssertEqual(note(), other)

        XCTAssertFalse(deepEqualFailures(note(), other).isEmpty)
    }
}
