import Foundation

/// Tracks search-related context
class SearchContext {
    private(set) var lastQuery: String?

    /// Update the last search query
    func updateQuery(_ query: String) {
        lastQuery = query
    }

    /// Clear search context
    func clear() {
        lastQuery = nil
    }
}
