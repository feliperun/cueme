import Foundation

@MainActor
extension AppModel {
    var historySearchResults: [SessionSearchResult] {
        historySearchResults(typeFilter: historyTypeFilter)
    }

    func historySearchResults(typeFilter: HistoryTypeFilter) -> [SessionSearchResult] {
        let scopedHistory = history.filter { record in
            (libraryProjectFilterID == nil || record.projectID == libraryProjectFilterID)
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

    var filteredHistory: [SessionRecord] {
        let records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        return historySearchResults.compactMap { records[$0.recordID] }
    }

}
