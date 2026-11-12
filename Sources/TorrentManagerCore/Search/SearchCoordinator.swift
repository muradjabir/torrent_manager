import Foundation

public struct SearchOutcome: Sendable {
    public let groups: [TorrentComparisonGroup]
    public let errors: [String]

    public init(groups: [TorrentComparisonGroup], errors: [String]) {
        self.groups = groups
        self.errors = errors
    }
}

public actor SearchCoordinator {
    private var indexers: [any TorrentIndexer] = []
    private let comparisonEngine = TorrentComparisonEngine()

    public init(indexers: [any TorrentIndexer] = []) {
        self.indexers = indexers
    }

    public func register(indexer: any TorrentIndexer) {
        indexers.append(indexer)
    }

    /// Performs a concurrent multi-indexer search with detailed outcome reporting.
    public func searchWithOutcome(
        query: String,
        category: TorrentCategory? = .all,
        limitPerIndexer: Int = 30
    ) async -> SearchOutcome {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchOutcome(groups: [], errors: [])
        }

        var aggregatedRawResults: [TorrentSearchResult] = []
        var errors: [String] = []

        struct SingleIndexerResult: Sendable {
            let indexerName: String
            let results: [TorrentSearchResult]
            let error: String?
        }

        await withTaskGroup(of: SingleIndexerResult.self) { group in
            for indexer in indexers {
                group.addTask {
                    do {
                        let res = try await indexer.search(query: query, category: category, limit: limitPerIndexer)
                        return SingleIndexerResult(indexerName: indexer.displayName, results: res, error: nil)
                    } catch {
                        return SingleIndexerResult(indexerName: indexer.displayName, results: [], error: "\(indexer.displayName): \(error.localizedDescription)")
                    }
                }
            }

            for await result in group {
                aggregatedRawResults.append(contentsOf: result.results)
                if let err = result.error {
                    errors.append(err)
                }
            }
        }

        let compared = comparisonEngine.aggregateAndCompare(results: aggregatedRawResults)
        return SearchOutcome(groups: compared, errors: errors)
    }

    /// Backwards-compatible simple search
    public func search(
        query: String,
        category: TorrentCategory? = .all,
        limitPerIndexer: Int = 30
    ) async -> [TorrentComparisonGroup] {
        let outcome = await searchWithOutcome(query: query, category: category, limitPerIndexer: limitPerIndexer)
        return outcome.groups
    }
}
