import Foundation

/// A single immutable result set for one middle-column render.
struct NoteListProjection {
    let scopedRecords: [SessionRecord]
    let visibleRecords: [SessionRecord]
    private let counts: [HistoryTypeFilter: Int]
    private let snippets: [UUID: String]

    init(
        history: [SessionRecord],
        searchResults: [SessionSearchResult],
        section: LibrarySection,
        selectedType: HistoryTypeFilter
    ) {
        let recordsByID = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        let searchedRecords = searchResults.compactMap { recordsByID[$0.recordID] }
        let scoped = Self.scope(searchedRecords, to: section)

        scopedRecords = scoped
        visibleRecords = selectedType == .all
            ? scoped
            : scoped.filter(selectedType.matches)
        counts = Self.counts(in: scoped)
        snippets = Self.snippets(from: searchResults, scopedTo: scoped)
    }

    func count(for filter: HistoryTypeFilter) -> Int {
        counts[filter] ?? scopedRecords.filter(filter.matches).count
    }

    func snippet(for recordID: UUID) -> String? {
        snippets[recordID]
    }

    private static func scope(
        _ records: [SessionRecord],
        to section: LibrarySection
    ) -> [SessionRecord] {
        switch section {
        case .all:
            return records
        case .inbox:
            return records.filter { $0.projectID == nil }
        case .journal:
            return records.filter { $0.libraryPresentationKind == .journal }
        }
    }

    private static func counts(in records: [SessionRecord]) -> [HistoryTypeFilter: Int] {
        [
            .all: records.count,
            .meeting: records.filter(HistoryTypeFilter.meeting.matches).count,
            .note: records.filter(HistoryTypeFilter.note.matches).count,
        ]
    }

    private static func snippets(
        from results: [SessionSearchResult],
        scopedTo records: [SessionRecord]
    ) -> [UUID: String] {
        let scopedIDs = Set(records.map(\.id))
        return results.reduce(into: [:]) { snippets, result in
            guard scopedIDs.contains(result.recordID),
                  let snippet = result.snippet,
                  !snippet.isEmpty else { return }
            snippets[result.recordID] = snippet
        }
    }
}
