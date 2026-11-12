import Foundation

/// Represents a source-specific report in a comparison group.
public struct TorrentSourceReport: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(indexerId)_\(infoHash)" }
    public let indexerId: String
    public let indexerName: String
    public let infoHash: String
    public let title: String
    public let reportedSeeders: Int
    public let reportedLeechers: Int
    public let reportedSizeBytes: Int64
    public let uploadDate: Date?
    public let verifiedUploader: Bool
    public let magnetURI: String
    public let detailURL: URL?
    public let health: SwarmHealth

    public init(from result: TorrentSearchResult) {
        self.indexerId = result.indexerId
        self.indexerName = result.indexerName
        self.infoHash = result.infoHash
        self.title = result.title
        self.reportedSeeders = result.seeders
        self.reportedLeechers = result.leechers
        self.reportedSizeBytes = result.sizeBytes
        self.uploadDate = result.uploadDate
        self.verifiedUploader = result.verifiedUploader
        self.magnetURI = result.magnetURI
        self.detailURL = result.detailURL
        self.health = result.health
    }
}

/// A grouped torrent release aggregated across one or more indexers with side-by-side comparison.
public struct TorrentComparisonGroup: Identifiable, Sendable, Codable, Equatable {
    public var id: String { infoHash }
    public let infoHash: String
    public let canonicalTitle: String
    public let category: TorrentCategory
    public let sizeBytes: Int64

    /// Maximum seeders observed across all reporting indexers.
    public let maxSeeders: Int
    /// Average seeders observed across indexers.
    public let averageSeeders: Double
    /// Maximum leechers observed across all reporting indexers.
    public let maxLeechers: Int

    /// Consolidated swarm health based on best swarm data.
    public let consolidatedHealth: SwarmHealth

    /// Super-magnet link containing deduplicated union of all announce trackers.
    public let unifiedMagnetURI: String

    /// Individual reports from each indexer for side-by-side comparison.
    public let sources: [TorrentSourceReport]

    /// True if all indexers report the exact same file size (within a 1KB margin).
    public let sizeConsistentAcrossSources: Bool

    /// Formatted size string.
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Announce tracker URLs extracted from the synthesized magnet.
    public var trackers: [String] {
        guard let components = URLComponents(string: unifiedMagnetURI) else { return [] }
        return components.queryItems?.filter { $0.name == "tr" }.compactMap { $0.value } ?? []
    }

    public init(
        infoHash: String,
        canonicalTitle: String,
        category: TorrentCategory,
        sizeBytes: Int64,
        maxSeeders: Int,
        averageSeeders: Double,
        maxLeechers: Int,
        consolidatedHealth: SwarmHealth,
        unifiedMagnetURI: String,
        sources: [TorrentSourceReport],
        sizeConsistentAcrossSources: Bool
    ) {
        self.infoHash = infoHash.lowercased()
        self.canonicalTitle = canonicalTitle
        self.category = category
        self.sizeBytes = sizeBytes
        self.maxSeeders = maxSeeders
        self.averageSeeders = averageSeeders
        self.maxLeechers = maxLeechers
        self.consolidatedHealth = consolidatedHealth
        self.unifiedMagnetURI = unifiedMagnetURI
        self.sources = sources
        self.sizeConsistentAcrossSources = sizeConsistentAcrossSources
    }
}

/// Engine that performs multi-indexer aggregation, deduplication, and comparative evaluation.
public struct TorrentComparisonEngine: Sendable {
    public init() {}

    /// Groups raw results from multiple indexers by info hash and generates comparative reports.
    public func aggregateAndCompare(results: [TorrentSearchResult]) -> [TorrentComparisonGroup] {
        var groupedByHash: [String: [TorrentSearchResult]] = [:]

        for result in results {
            let hash = result.infoHash.lowercased()
            guard !hash.isEmpty, hash != "0000000000000000000000000000000000000000" else {
                continue
            }
            groupedByHash[hash, default: []].append(result)
        }

        var groups: [TorrentComparisonGroup] = []

        for (infoHash, groupResults) in groupedByHash {
            let sortedBySeeds = groupResults.sorted { $0.seeders > $1.seeders }
            guard let primary = sortedBySeeds.first else { continue }

            let canonicalTitle = primary.title
            let category = primary.category
            let sizeBytes = primary.sizeBytes

            let maxSeeders = groupResults.map(\.seeders).max() ?? 0
            let totalSeeds = groupResults.reduce(0) { $0 + $1.seeders }
            let averageSeeders = Double(totalSeeds) / Double(groupResults.count)
            let maxLeechers = groupResults.map(\.leechers).max() ?? 0

            let consolidatedHealth = SwarmHealth(seeders: maxSeeders, leechers: maxLeechers)

            // Check size consistency
            let sizes = groupResults.map(\.sizeBytes)
            let minSize = sizes.min() ?? 0
            let maxSize = sizes.max() ?? 0
            let sizeConsistent = (maxSize - minSize) < 1024

            // Merge all unique trackers into a unified magnet
            let unifiedMagnet = buildUnifiedMagnet(infoHash: infoHash, title: canonicalTitle, magnetURIs: groupResults.map(\.magnetURI))

            let sources = groupResults.map { TorrentSourceReport(from: $0) }

            groups.append(TorrentComparisonGroup(
                infoHash: infoHash,
                canonicalTitle: canonicalTitle,
                category: category,
                sizeBytes: sizeBytes,
                maxSeeders: maxSeeders,
                averageSeeders: averageSeeders,
                maxLeechers: maxLeechers,
                consolidatedHealth: consolidatedHealth,
                unifiedMagnetURI: unifiedMagnet,
                sources: sources,
                sizeConsistentAcrossSources: sizeConsistent
            ))
        }

        // Sort descending by maximum seeders by default
        return groups.sorted { $0.maxSeeders > $1.maxSeeders }
    }

    /// Merges announce trackers from multiple magnet URIs into one unified URI.
    public func buildUnifiedMagnet(infoHash: String, title: String, magnetURIs: [String]) -> String {
        var trackerSet: Set<String> = []

        for uri in magnetURIs {
            if let components = URLComponents(string: uri) {
                for item in components.queryItems ?? [] where item.name == "tr" {
                    if let val = item.value, !val.isEmpty {
                        trackerSet.insert(val)
                    }
                }
            }
        }

        // Include default fallback trackers if few were found
        for defaultTracker in CustomRESTIndexer.standardTrackers {
            trackerSet.insert(defaultTracker)
        }

        var components = URLComponents()
        components.scheme = "magnet"
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "xt", value: "urn:btih:\(infoHash.uppercased())"),
            URLQueryItem(name: "dn", value: title)
        ]

        for tracker in trackerSet.sorted() {
            queryItems.append(URLQueryItem(name: "tr", value: tracker))
        }

        components.queryItems = queryItems
        return components.string ?? "magnet:?xt=urn:btih:\(infoHash)"
    }
}

