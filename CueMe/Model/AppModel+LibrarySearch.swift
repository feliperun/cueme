import Foundation

@MainActor
extension AppModel {
    var historySearchResults: [SessionSearchResult] {
        historySearchResults(typeFilter: historyTypeFilter)
    }

    func historySearchResults(typeFilter: HistoryTypeFilter) -> [SessionSearchResult] {
        // Scoping is by subtree: selecting a node in the tree means "this note
        // and everything under it", which is what "belongs to" now means.
        let scoped = librarySubtreeNoteID.map { Set(noteSubtree(of: $0).map(\.id)) }
        let scopedHistory = history.filter { record in
            (scoped == nil || scoped?.contains(record.id) == true)
                && (libraryLabelFilter == nil || record.labels.contains(libraryLabelFilter ?? ""))
        }
        let cleanQuery = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanQuery.isEmpty {
            return scopedHistory
                .filter { historyDateFilter.contains($0.startedAt, now: Date()) && typeFilter.matches($0) }
                .sorted { $0.startedAt > $1.startedAt }
                .map { SessionSearchResult(recordID: $0.id, score: 0, snippet: nil) }
        }
        let hybrid = searchSemanticMemory(
            query: cleanQuery,
            date: historyDateFilter,
            type: typeFilter,
            records: scopedHistory
        )
        if !hybrid.isEmpty {
            return hybrid
        }
        return SessionKnowledgeIndex(records: scopedHistory)
            .search(query: cleanQuery, date: historyDateFilter, type: typeFilter)
    }

    var filteredHistory: [MemoryNote] {
        let records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        return historySearchResults.compactMap { records[$0.recordID] }
    }

}
