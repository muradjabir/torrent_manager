import Foundation

public enum ClientType: String, Sendable, Codable, CaseIterable {
    case deluge = "deluge"
    case transmission = "transmission"
    case qbittorrent = "qbittorrent"
    case localApp = "localApp"

    public var displayName: String {
        switch self {
        case .deluge: return "Deluge (Web JSON-RPC)"
        case .transmission: return "Transmission (RPC)"
        case .qbittorrent: return "qBittorrent (Web API)"
        case .localApp: return "Default macOS Client"
        }
    }
}

public struct ConnectionTestResult: Sendable, Codable, Equatable {
    public let isSuccessful: Bool
    public let serverVersion: String?
    public let errorMessage: String?

    public init(isSuccessful: Bool, serverVersion: String? = nil, errorMessage: String? = nil) {
        self.isSuccessful = isSuccessful
        self.serverVersion = serverVersion
        self.errorMessage = errorMessage
    }
}

public protocol TorrentClientProtocol: Sendable {
    var clientType: ClientType { get }
    var connectionName: String { get }

    func testConnection() async throws -> ConnectionTestResult
    func addTorrent(magnetURI: String, options: AddTorrentOptions) async throws -> String
    func listTorrents() async throws -> [TorrentItem]
    func pauseTorrent(id: String) async throws
    func resumeTorrent(id: String) async throws
    func removeTorrent(id: String, deleteData: Bool) async throws
}

