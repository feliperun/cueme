import Foundation

/// JSON serialization for the transitional `session.json` sidecar and the
/// recursive scan that finds them. Split out of `SessionStore`, which owns
/// where a note lives; T014 deletes this file with the sidecar itself.
enum SessionArchiveCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func loadArchive() -> [MemoryNote] {
        guard let enumerator = FileManager.default.enumerator(
            at: SessionStore.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var records: [MemoryNote] = []
        for case let url as URL in enumerator where url.lastPathComponent == "session.json" {
            guard var record = try? decoder.decode(MemoryNote.self, from: Data(contentsOf: url)) else { continue }
            let folder = url.deletingLastPathComponent()
            let relative = folder.path.replacingOccurrences(of: SessionStore.rootURL.path + "/", with: "")
            if !relative.isEmpty, relative != folder.path { record.relativeFolderPath = relative }
            record = NoteDocument.mergeCanonicalFields(
                from: folder.appendingPathComponent(NoteDocument.filename),
                into: record
            )
            records.append(record)
        }
        return records
    }
}
