import Foundation

/// Reads and writes the user's custom vocabulary. Split out of
/// `CustomVocabulary`, which is the value itself.
enum CustomVocabularyStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vocabulary.json")
    }

    static func load() -> CustomVocabulary {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(CustomVocabulary.self, from: data) else { return .init() }
        return value
    }

    static func save(_ vocabulary: CustomVocabulary) {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
