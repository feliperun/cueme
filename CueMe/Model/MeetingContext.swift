import CryptoKit
import Foundation

/// Reusable source material selected before a session (product, customer,
/// project, role, company, domain, etc.). Contexts stay local until the user
/// asks the selected LLM to derive a Deepgram glossary from them.
struct MeetingContext: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var content: String

    init(id: UUID = UUID(), name: String, content: String = "") {
        self.id = id
        self.name = name
        self.content = content
    }
}

enum GlossaryGenerationState: Equatable {
    case idle
    case generating
    case ready(Int)
    case failed(String)
}

struct ContextGlossaryCache: Codable, Sendable, Equatable {
    var signature: String
    var model: CoachModel
    var terms: [String]
    var generatedAt: Date
}

/// Shared boundary policy for generated, learned and manually entered terms.
/// Deepgram documents a maximum of 100 keyterms / 500 aggregate tokens.
enum MeetingContextStore {
    private static let selectedKey = "selectedMeetingContextIDs"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load() -> [MeetingContext] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("contexts.json")),
              let contexts = try? JSONDecoder().decode([MeetingContext].self, from: data) else { return [] }
        return contexts
    }

    static func save(_ contexts: [MeetingContext]) {
        guard let data = try? JSONEncoder().encode(contexts) else { return }
        try? data.write(to: directory.appendingPathComponent("contexts.json"), options: .atomic)
    }

    static func loadSelection() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(forKey: selectedKey) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func saveSelection(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: selectedKey)
    }

    static func loadCache() -> ContextGlossaryCache? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("context-glossary.json")) else {
            return nil
        }
        return try? JSONDecoder().decode(ContextGlossaryCache.self, from: data)
    }

    static func saveCache(_ cache: ContextGlossaryCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: directory.appendingPathComponent("context-glossary.json"), options: .atomic)
    }
}
