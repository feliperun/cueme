import XCTest
@testable import CueMe

/// AC2 and AC5 — the runtime diagnostics log lives outside the user's corpus and
/// rotates away anything older than 7 days. Every test injects both the base
/// directory and the clock; none of this may touch the real
/// `~/Library/Logs/CueMe` or the wall clock.
final class DiagnosticsLogTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsLogTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    func testDiagnosticsLogWritesOutsideTheCorpus() throws {
        let corpusRoot = tempRoot.appendingPathComponent("corpus", isDirectory: true)
        let logsRoot = tempRoot.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: corpusRoot, withIntermediateDirectories: true)

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let log = DiagnosticsLog(baseDirectory: logsRoot, now: { fixedNow })
        log.record(.init(at: fixedNow, kind: .session, name: "started"))

        let written = try FileManager.default.contentsOfDirectory(
            at: logsRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(written.count, 1)
        let file = try XCTUnwrap(written.first)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("diagnostics-"))
        XCTAssertTrue(file.pathExtension == "jsonl")
        XCTAssertFalse(
            file.standardizedFileURL.path.hasPrefix(corpusRoot.standardizedFileURL.path),
            "diagnostics files must never land inside the corpus root"
        )

        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"name\":\"started\""))
    }

    func testRotationDropsLogsOlderThanSevenDays() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let oldFile = tempRoot.appendingPathComponent("diagnostics-2020-01-01.jsonl")
        let recentFile = tempRoot.appendingPathComponent("diagnostics-2020-01-08.jsonl")
        try "{}\n".write(to: oldFile, atomically: true, encoding: .utf8)
        try "{}\n".write(to: recentFile, atomically: true, encoding: .utf8)

        // 2020-01-11 is 10 days after the old file's date and 3 days after the
        // recent one — only the old file crosses the 7-day retention window.
        let rotationDay = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2020, month: 1, day: 11
        ).date!
        let log = DiagnosticsLog(baseDirectory: tempRoot, now: { rotationDay })
        log.record(.init(at: rotationDay, kind: .session, name: "started"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path), "log older than 7 days must be dropped")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path), "log within 7 days must survive")
    }
}
