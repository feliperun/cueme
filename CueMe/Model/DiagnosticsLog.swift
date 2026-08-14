import Foundation

/// Runtime dev telemetry: an in-memory ring for the current session plus an
/// append-only JSONL file per day, rotated after 7 days. Deliberately outside
/// the user's corpus — see ADR 0045. `MemoryNote.integrity` is the only piece
/// of this that a saved note ever carries.
final class DiagnosticsLog: @unchecked Sendable {
    nonisolated(unsafe) static var rootOverride: URL?

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/CueMe", isDirectory: true)
    }

    private static let retentionDays = 7

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let eventEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let baseDirectory: URL
    private let now: () -> Date
    private var session = SessionDiagnostics()

    init(baseDirectory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.baseDirectory = baseDirectory ?? Self.rootOverride ?? Self.defaultBaseDirectory
        self.now = now
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }

    /// Clears the in-memory ring for a fresh session. The JSONL history on disk
    /// is untouched — it is cumulative dev telemetry, not per-session state.
    func resetSession() {
        session = SessionDiagnostics()
    }

    func record(_ event: DiagnosticEvent) {
        session.record(event)
        append(event)
        rotate()
    }

    func count(_ name: String) -> Int { session.count(name) }
    func count(kind: DiagnosticEvent.Kind) -> Int { session.count(kind: kind) }

    /// The two counters a note is allowed to keep (AC1).
    var integrity: NoteIntegrity {
        NoteIntegrity(recoveries: session.count(kind: .recovery), errors: session.count(kind: .error))
    }

    private func fileURL(for date: Date) -> URL {
        baseDirectory.appendingPathComponent("diagnostics-\(Self.fileDateFormatter.string(from: date)).jsonl")
    }

    private func append(_ event: DiagnosticEvent) {
        guard var line = try? Self.eventEncoder.encode(event) else { return }
        line.append(0x0A)
        let url = fileURL(for: now())
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: line)
        }
    }

    /// Drops any `diagnostics-yyyy-MM-dd.jsonl` file more than 7 days older
    /// than `now()`, judged by the date encoded in its filename — never by
    /// filesystem mtime, so this stays deterministic under an injected clock.
    private func rotate() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = now()
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("diagnostics-"), file.pathExtension == "jsonl" else { continue }
            let stamp = String(name.dropFirst("diagnostics-".count).dropLast(".jsonl".count))
            guard let fileDate = Self.fileDateFormatter.date(from: stamp) else { continue }
            let age = calendar.dateComponents([.day], from: fileDate, to: today).day ?? 0
            if age > Self.retentionDays {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
