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
        let hybrid = searchSemanticMemory(
            query: historySearch,
            date: historyDateFilter,
            type: typeFilter,
            records: scopedHistory
        )
        if !hybrid.isEmpty || historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hybrid
        }
        return SessionKnowledgeIndex(records: scopedHistory)
            .search(query: historySearch, date: historyDateFilter, type: typeFilter)
    }

    var filteredHistory: [SessionRecord] {
        let records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        return historySearchResults.compactMap { records[$0.recordID] }
    }

}
