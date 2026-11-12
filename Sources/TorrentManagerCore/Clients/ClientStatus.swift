import Foundation

public struct ClientStatusInfo: Sendable, Codable, Equatable {
    public let isOnline: Bool
    public let serverVersion: String?
    public let torrentCount: Int
    public let downloadRateBytesPerSec: Int64
    public let uploadRateBytesPerSec: Int64
    public let errorMessage: String?
    public let lastChecked: Date

    public init(
        isOnline: Bool,
        serverVersion: String? = nil,
        torrentCount: Int = 0,
        downloadRateBytesPerSec: Int64 = 0,
        uploadRateBytesPerSec: Int64 = 0,
        errorMessage: String? = nil,
        lastChecked: Date = Date()
    ) {
        self.isOnline = isOnline
        self.serverVersion = serverVersion
        self.torrentCount = torrentCount
        self.downloadRateBytesPerSec = downloadRateBytesPerSec
        self.uploadRateBytesPerSec = uploadRateBytesPerSec
        self.errorMessage = errorMessage
        self.lastChecked = lastChecked
    }

    public var formattedDownloadSpeed: String {
        formatSpeed(downloadRateBytesPerSec)
    }

    public var formattedUploadSpeed: String {
        formatSpeed(uploadRateBytesPerSec)
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB/s", mb)
    }
}

