import Foundation

public struct IndexerCapabilities: Sendable, Codable {
    public let supportsCategories: Bool
    public let supportsFileDetails: Bool
    public let supportsSorting: Bool

    public init(supportsCategories: Bool, supportsFileDetails: Bool, supportsSorting: Bool) {
        self.supportsCategories = supportsCategories
        self.supportsFileDetails = supportsFileDetails
        self.supportsSorting = supportsSorting
    }
}

public protocol TorrentIndexer: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: IndexerCapabilities { get }

    func search(
        query: String,
        category: TorrentCategory?,
        limit: Int
    ) async throws -> [TorrentSearchResult]

    func fetchFiles(id: String, infoHash: String) async throws -> [TorrentFileInfo]
}

