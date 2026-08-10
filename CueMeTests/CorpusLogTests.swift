import XCTest
@testable import CueMe

/// `log.md` is append-only. The assertion that matters is not how many entries
/// exist — it is that everything already written is still byte-for-byte where
/// it was.
final class CorpusLogTests: XCTestCase {
    private var root: URL!
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeLog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CorpusStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        CorpusStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc
        return formatter.date(from: iso)!
    }

    private func logging(_ sentence: String, _ operation: CorpusLogDocument.Operation, on date: Date, to existing: String?) -> String {
        CorpusLogDocument.appending(sentence, operation: operation, on: date, to: existing, timeZone: utc)
    }

    // MARK: AC1 — two entries the same day, and not one earlier byte moves

    func testSecondEntrySameDayLeavesHistoryByteIdentical() {
        let first = logging(
            "[Acme](acme.md) criada.", .created, on: instant("2026-08-08T09:00:00Z"), to: nil
        )
        let second = logging(
            "[Ata](acme/ata.md) movida para [Acme](acme.md).",
            .moved, on: instant("2026-08-08T17:30:00Z"), to: first
        )

        XCTAssertTrue(
            second.hasPrefix(first.hasSuffix("\n") ? String(first.dropLast()) : first),
            "an append must not rewrite a single byte of what was already there"
        )
        XCTAssertEqual(second, """
        # Histórico do corpus

        ## 2026-08-08

        - **Criação**: [Acme](acme.md) criada.
        - **Movimentação**: [Ata](acme/ata.md) movida para [Acme](acme.md).

        """)
        XCTAssertEqual(second.components(separatedBy: "## 2026-08-08").count - 1, 1, "one group per day")
    }

    // MARK: AC7 — a newer day opens a group at the top

    func testNewDayCreatesGroupAtTheTop() {
        let first = logging("214 notas importadas.", .migrated, on: instant("2026-08-08T09:00:00Z"), to: nil)
        let second = logging(
            "[Acme](acme.md) renomeada de `conta-acme`; 4 páginas com links atualizados.",
            .renamed, on: instant("2026-08-09T11:00:00Z"), to: first
        )

        XCTAssertEqual(second, """
        # Histórico do corpus

        ## 2026-08-09

        - **Renomeação**: [Acme](acme.md) renomeada de `conta-acme`; 4 páginas com links atualizados.

        ## 2026-08-08

        - **Migração**: 214 notas importadas.

        """)
        XCTAssertTrue(
            second.contains("## 2026-08-08\n\n- **Migração**: 214 notas importadas."),
            "the older group survives untouched below the new one"
        )
        XCTAssertLessThan(
            second.range(of: "## 2026-08-09")!.lowerBound,
            second.range(of: "## 2026-08-08")!.lowerBound,
            "newest group first"
        )
    }

    func testAnOlderEntryLandsBelowTheNewerGroups() {
        var log = logging("Nova.", .created, on: instant("2026-08-09T10:00:00Z"), to: nil)
        log = logging("Antiga.", .created, on: instant("2026-08-07T10:00:00Z"), to: log)

        XCTAssertLessThan(
            log.range(of: "## 2026-08-09")!.lowerBound,
            log.range(of: "## 2026-08-07")!.lowerBound
        )
    }

    // MARK: through the store

    func testAppendingThroughTheStorePreservesTheFileOnDisk() throws {
        CorpusStore.appendLog(
            "[Acme](acme.md) criada.", operation: .created,
            on: instant("2026-08-08T09:00:00Z"), timeZone: utc
        )
        let url = root.appendingPathComponent("log.md")
        let after1 = try String(contentsOf: url, encoding: .utf8)

        CorpusStore.appendLog(
            "pasta `acme/orfa/` sem nota irmã.", operation: .inconsistency,
            on: instant("2026-08-08T12:00:00Z"), timeZone: utc
        )
        let after2 = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(after2.contains("- **Criação**: [Acme](acme.md) criada."))
        XCTAssertTrue(after2.contains("- **Inconsistência**: pasta `acme/orfa/` sem nota irmã."))
        XCTAssertTrue(
            after2.hasPrefix(after1.hasSuffix("\n") ? String(after1.dropLast()) : after1),
            "the file on disk grows at the end; it is never regenerated"
        )
    }
}
