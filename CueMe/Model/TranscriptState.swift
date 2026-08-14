import Foundation

/// Whether a note's transcript is in memory.
///
/// The transcript is captured material and lives in its own file under the
/// note's `raw/` directory, so loading the library must not read it. That makes
/// a lazily-empty transcript representable — and saving one would erase the file
/// on disk. This type is what makes that unrepresentable instead: writing is
/// gated on `.loaded`, so a transcript that was never read cannot be written
/// away. See `specs/okf-corpus/design.md` §7.
///
/// Reading is deliberately permissive: the state behaves as a collection of its
/// lines, empty when not loaded, so every existing reader keeps working.
enum TranscriptState: Codable, Sendable, Hashable {
    case notLoaded(turns: Int)
    case loaded([TranscriptLine])

    var lines: [TranscriptLine] {
        switch self {
        case .notLoaded: return []
        case .loaded(let lines): return lines
        }
    }

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Number of final turns, correct in both cases. Only final turns are ever
    /// written to disk, so the count carried by `.notLoaded` is a count of finals.
    var turnCount: Int {
        switch self {
        case .notLoaded(let turns): return turns
        case .loaded(let lines): return lines.filter(\.isFinal).count
        }
    }

    /// Applies `transform` to the line with `id`. A no-op when the transcript
    /// is not loaded: correcting a line that was never read is not meaningful,
    /// and rebuilding the state from an empty array here would be the very
    /// erasure this type exists to prevent.
    mutating func updateLine(id: UUID, _ transform: (inout TranscriptLine) -> Void) {
        guard case .loaded(var lines) = self,
              let index = lines.firstIndex(where: { $0.id == id }) else { return }
        transform(&lines[index])
        self = .loaded(lines)
    }

    private enum CodingKeys: String, CodingKey { case state, turns, lines }
    private enum State: String, Codable { case notLoaded, loaded }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded(let turns):
            try c.encode(State.notLoaded, forKey: .state)
            try c.encode(turns, forKey: .turns)
        case .loaded(let lines):
            try c.encode(State.loaded, forKey: .state)
            try c.encode(lines, forKey: .lines)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(State.self, forKey: .state) {
        case .notLoaded:
            self = .notLoaded(turns: try c.decode(Int.self, forKey: .turns))
        case .loaded:
            self = .loaded(try c.decode([TranscriptLine].self, forKey: .lines))
        }
    }
}

extension TranscriptState: RandomAccessCollection {
    var startIndex: Int { lines.startIndex }
    var endIndex: Int { lines.endIndex }
    subscript(position: Int) -> TranscriptLine { lines[position] }
    func index(after i: Int) -> Int { lines.index(after: i) }
    func index(before i: Int) -> Int { lines.index(before: i) }
}
