import Foundation

/// Metadata-only session telemetry. It intentionally excludes transcript text,
/// audio samples, credentials, prompts, and provider responses.
struct DiagnosticEvent: Codable, Sendable, Hashable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case session, capture, transcription, coach, summary, recovery, error
    }

    let id: UUID
    let at: Date
    let kind: Kind
    let name: String
    let speaker: Speaker?
    let durationMs: Int64?
    let detail: String?

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: Kind,
        name: String,
        speaker: Speaker? = nil,
        durationMs: Int64? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.name = name
        self.speaker = speaker
        self.durationMs = durationMs
        self.detail = detail
    }
}

struct DiagnosticAggregate: Codable, Sendable, Hashable {
    var count = 0
    var totalDurationMs: Int64 = 0
    var durationSamples = 0
    var maxDurationMs: Int64 = 0
    var durationValues: [Int64]? = []

    mutating func record(durationMs: Int64?) {
        count += 1
        guard let durationMs else { return }
        totalDurationMs += durationMs
        durationSamples += 1
        maxDurationMs = max(maxDurationMs, durationMs)
        durationValues?.append(durationMs)
        if let count = durationValues?.count, count > 1_000 {
            durationValues?.removeFirst(count - 1_000)
        }
    }
}

struct SessionDiagnostics: Codable, Sendable, Hashable {
    var events: [DiagnosticEvent] = []
    private var aggregates: [String: DiagnosticAggregate] = [:]
    private var kindCounts: [DiagnosticEvent.Kind: Int] = [:]

    mutating func record(_ event: DiagnosticEvent) {
        events.append(event)
        aggregates[event.name, default: .init()].record(durationMs: event.durationMs)
        kindCounts[event.kind, default: 0] += 1
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func count(_ name: String) -> Int {
        aggregates[name]?.count ?? events.lazy.filter { $0.name == name }.count
    }

    func averageMs(_ name: String) -> Int64? {
        if let aggregate = aggregates[name], aggregate.durationSamples > 0 {
            return aggregate.totalDurationMs / Int64(aggregate.durationSamples)
        }
        let values = events.lazy.filter { $0.name == name }.compactMap(\.durationMs)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }

    func count(kind: DiagnosticEvent.Kind) -> Int {
        kindCounts[kind] ?? events.lazy.filter { $0.kind == kind }.count
    }

    func durationValues(_ name: String) -> [Int64] {
        aggregates[name]?.durationValues ?? events.lazy.filter { $0.name == name }.compactMap(\.durationMs)
    }

    private enum CodingKeys: String, CodingKey { case events, aggregates, kindCounts }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([DiagnosticEvent].self, forKey: .events) ?? []
        aggregates = try container.decodeIfPresent([String: DiagnosticAggregate].self, forKey: .aggregates) ?? [:]
        kindCounts = try container.decodeIfPresent([DiagnosticEvent.Kind: Int].self, forKey: .kindCounts) ?? [:]
        if aggregates.isEmpty {
            for event in events { aggregates[event.name, default: .init()].record(durationMs: event.durationMs) }
        }
        if kindCounts.isEmpty {
            for event in events { kindCounts[event.kind, default: 0] += 1 }
        }
    }
}
