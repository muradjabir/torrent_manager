import Foundation

/// Universal category mapping for torrent content.
public enum TorrentCategory: String, CaseIterable, Sendable, Codable {
    case all = "all"
    case video = "video"
    case audio = "audio"
    case applications = "applications"
    case games = "games"
    case other = "other"

    public var displayName: String {
        switch self {
        case .all: return "All Categories"
        case .video: return "Video / Movies / TV"
        case .audio: return "Audio / Music"
        case .applications: return "Applications / Software"
        case .games: return "Games"
        case .other: return "Other"
        }
    }
}

/// Sort criteria for searching indexers.
public enum SortCriteria: String, Sendable, Codable {
    case seedersDesc
    case seedersAsc
    case sizeDesc
    case sizeAsc
    case dateDesc
    case dateAsc
    case healthDesc
}

/// Swarm Health breakdown and calculation.
public struct SwarmHealth: Sendable, Codable, Equatable {
    public let score: Double // 0 to 100
    public let label: String
    public let statusColor: String // "green", "yellow", "red"

    public init(seeders: Int, leechers: Int) {
        if seeders == 0 {
            self.score = 0
            self.label = "Dead"
            self.statusColor = "red"
            return
        }

        // Health score algorithm:
        // 1. Seeder/Leecher ratio factor (up to 40 pts)
        let total = Double(seeders + leechers)
        let ratio = total > 0 ? (Double(seeders) / total) : 0.0
        let ratioScore = ratio * 40.0

        // 2. Absolute seed count scaling factor (up to 60 pts using logarithmic scale)
        // 1 seeder -> ~0 pts, 10 seeders -> ~25 pts, 50 seeders -> ~45 pts, 200+ seeders -> ~60 pts
        let logScale = min(1.0, log10(Double(seeders) + 1.0) / log10(200.0))
        let seedScore = logScale * 60.0

        let totalScore = min(100.0, max(0.0, ratioScore + seedScore))
        self.score = (totalScore * 10).rounded() / 10

        if totalScore >= 75.0 {
            self.label = "Excellent"
            self.statusColor = "green"
        } else if totalScore >= 45.0 {
            self.label = "Healthy"
            self.statusColor = "green"
        } else if totalScore >= 20.0 {
            self.label = "Moderate"
            self.statusColor = "yellow"
        } else {
            self.label = "Poor"
            self.statusColor = "red"
        }
    }
}

/// A search result returned by any indexer.
public struct TorrentSearchResult: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let infoHash: String
    public let sizeBytes: Int64
    public let seeders: Int
    public let leechers: Int
    public let category: TorrentCategory
    public let uploadDate: Date?
    public let magnetURI: String
    public let indexerId: String
    public let indexerName: String
    public let health: SwarmHealth
    public let verifiedUploader: Bool
    public let detailURL: URL?

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    public init(
        id: String,
        title: String,
        infoHash: String,
        sizeBytes: Int64,
        seeders: Int,
        leechers: Int,
        category: TorrentCategory,
        uploadDate: Date?,
        magnetURI: String,
        indexerId: String,
        indexerName: String,
        verifiedUploader: Bool = false,
        detailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.infoHash = infoHash.lowercased()
        self.sizeBytes = sizeBytes
        self.seeders = seeders
        self.leechers = leechers
        self.category = category
        self.uploadDate = uploadDate
        self.magnetURI = magnetURI
        self.indexerId = indexerId
        self.indexerName = indexerName
        self.verifiedUploader = verifiedUploader
        self.detailURL = detailURL
        self.health = SwarmHealth(seeders: seeders, leechers: leechers)
    }
}

/// Detailed file representation within a torrent.
public struct TorrentFileInfo: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let sizeBytes: Int64

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    public init(id: String, name: String, sizeBytes: Int64) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

/// Download/transfer state within a torrent client.
public enum TorrentTransferState: String, Sendable, Codable, CaseIterable {
    case downloading
    case seeding
    case paused
    case queued
    case checking
    case error
    case unknown

    public var displayName: String {
        switch self {
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .paused: return "Paused"
        case .queued: return "Queued"
        case .checking: return "Checking"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }

    public var iconName: String {
        switch self {
        case .downloading: return "arrow.down.circle.fill"
        case .seeding: return "arrow.up.circle.fill"
        case .paused: return "pause.circle.fill"
        case .queued: return "clock.fill"
        case .checking: return "arrow.triangle.2.circlepath.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Live torrent item retrieved from a connected client.
public struct TorrentItem: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let totalSizeBytes: Int64
    public let completedBytes: Int64
    public let progress: Double // 0.0 to 1.0
    public let downloadSpeedBytesPerSec: Int64
    public let uploadSpeedBytesPerSec: Int64
    public let etaSeconds: Int?
    public let state: TorrentTransferState
    public let connectedSeeds: Int
    public let connectedLeechers: Int

    public var formattedProgress: String {
        String(format: "%.1f%%", progress * 100)
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSizeBytes)
    }

    public var formattedCompleted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: completedBytes)
    }

    public var formattedDownSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: downloadSpeedBytesPerSec))/s"
    }

    public var formattedUpSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: uploadSpeedBytesPerSec))/s"
    }

    public var formattedETA: String {
        guard let eta = etaSeconds, eta > 0 else { return "—" }
        if eta < 60 { return "\(eta)s" }
        let mins = eta / 60
        let secs = eta % 60
        if mins < 60 { return "\(mins)m \(secs)s" }
        let hours = mins / 60
        let remMins = mins % 60
        return "\(hours)h \(remMins)m"
    }

    public init(
        id: String,
        name: String,
        totalSizeBytes: Int64,
        completedBytes: Int64,
        progress: Double,
        downloadSpeedBytesPerSec: Int64,
        uploadSpeedBytesPerSec: Int64,
        etaSeconds: Int?,
        state: TorrentTransferState,
        connectedSeeds: Int = 0,
        connectedLeechers: Int = 0
    ) {
        self.id = id
        self.name = name
        self.totalSizeBytes = totalSizeBytes
        self.completedBytes = completedBytes
        self.progress = progress
        self.downloadSpeedBytesPerSec = downloadSpeedBytesPerSec
        self.uploadSpeedBytesPerSec = uploadSpeedBytesPerSec
        self.etaSeconds = etaSeconds
        self.state = state
        self.connectedSeeds = connectedSeeds
        self.connectedLeechers = connectedLeechers
    }
}

/// Options when dispatching a torrent to a client.
public struct AddTorrentOptions: Sendable, Codable {
    public var downloadDirectory: String?
    public var startPaused: Bool
    public var tags: [String]

    public init(downloadDirectory: String? = nil, startPaused: Bool = false, tags: [String] = []) {
        self.downloadDirectory = downloadDirectory
        self.startPaused = startPaused
        self.tags = tags
    }
}

