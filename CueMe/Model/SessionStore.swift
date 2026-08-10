import Foundation

/// Thin facade over `CorpusStore`, kept only because `ProjectWorkspaceStore`
/// (deleted whole in T016, per `specs/okf-corpus/design.md` §9) still depends
/// on this exact surface. Every member here forwards to `CorpusStore`, which
/// is the real implementation as of T013 — see
/// `specs/okf-corpus/tasks/T013-corpus-store.md`.
enum SessionStore {
    static var rootOverride: URL? {
        get { CorpusStore.rootOverride }
        set { CorpusStore.rootOverride = newValue }
    }

    static var rootURL: URL { CorpusStore.rootURL }

    static func setRoot(_ url: URL) throws { try CorpusStore.setRoot(url) }

    static func archiveDirectory(for record: MemoryNote) -> URL { CorpusStore.noteFolder(for: record) }

    @discardableResult
    static func prepareSession(id: UUID, startedAt: Date) -> URL? {
        CorpusStore.prepareNote(id: id, startedAt: startedAt, under: CorpusStore.defaultInboxNote())
    }

    @discardableResult
    static func save(_ record: MemoryNote) -> URL? { CorpusStore.save(record) }

    static func loadAll() -> [MemoryNote] {
        CorpusStore.loadNotes().sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ record: MemoryNote) {
        CorpusStore.delete(record)
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
