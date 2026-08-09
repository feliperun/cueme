import Foundation

/// Filesystem side of the archive: where a note's folder lives, and the
/// read, write, move and delete operations over it. Split out of
/// `SessionArchive`, which is the Markdown rendering side.
enum SessionStore {
    nonisolated(unsafe) static var rootOverride: URL?
    private static let configuredRootKey = "sessionArchiveRootPath"

    static var rootURL: URL {
        if let rootOverride { return rootOverride }
        if let path = UserDefaults.standard.string(forKey: configuredRootKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CueMe/Session Archive", isDirectory: true)
    }

    static var hasCustomRoot: Bool {
        UserDefaults.standard.string(forKey: configuredRootKey) != nil
    }

    static func setRoot(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: configuredRootKey)
    }

    static func archiveDirectory(for record: MemoryNote) -> URL {
        rootURL.appendingPathComponent(record.storageRelativePath, isDirectory: true)
    }

    static func prepareSession(id: UUID, startedAt: Date) -> URL? {
        let directory = rootURL.appendingPathComponent("_Inbox", isDirectory: true)
            .appendingPathComponent(SessionArchive.folderName(startedAt: startedAt, id: id), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    @discardableResult
    static func save(_ record: MemoryNote) -> URL? {
        let directory = archiveDirectory(for: record)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try SessionArchiveCodec.encoder.encode(record)
            try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)
            let markdown = SessionArchive.markdown(for: record)
            try markdown.write(
                to: directory.appendingPathComponent(NoteDocument.filename),
                atomically: true,
                encoding: .utf8
            )
            return directory
        } catch {
            return nil
        }
    }

    static func loadAll() -> [MemoryNote] {
        var records: [UUID: MemoryNote] = [:]
        for record in SessionArchiveCodec.loadArchive() { records[record.id] = record }
        return records.values.sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ record: MemoryNote) {
        try? FileManager.default.removeItem(at: archiveDirectory(for: record))
        MeetingRecording.deleteLegacy(for: record.id)
    }

    static func delete(_ id: UUID) {
        if let record = loadAll().first(where: { $0.id == id }) {
            delete(record)
        } else {
            MeetingRecording.deleteLegacy(for: id)
        }
    }

}
