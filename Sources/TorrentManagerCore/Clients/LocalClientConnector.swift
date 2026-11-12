import Foundation
#if canImport(AppKit)
import AppKit
#endif

public final class LocalClientConnector: TorrentClientProtocol, @unchecked Sendable {
    public let clientType: ClientType = .localApp
    public let connectionName: String = "Local macOS Default App"

    public init() {}

    public func testConnection() async throws -> ConnectionTestResult {
        #if canImport(AppKit)
        if let dummyURL = URL(string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000") {
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: dummyURL)
            if let appName = appURL?.deletingPathExtension().lastPathComponent {
                return ConnectionTestResult(isSuccessful: true, serverVersion: appName)
            }
        }
        return ConnectionTestResult(isSuccessful: true, serverVersion: "Default magnet handler")
        #else
        return ConnectionTestResult(isSuccessful: false, errorMessage: "AppKit not available")
        #endif
    }

    public func addTorrent(magnetURI: String, options: AddTorrentOptions) async throws -> String {
        guard let url = URL(string: magnetURI) else {
            throw URLError(.badURL)
        }

        #if canImport(AppKit)
        return await MainActor.run {
            let success = NSWorkspace.shared.open(url)
            if success {
                return "Opened in default macOS client"
            } else {
                return "Failed to open magnet in default application"
            }
        }
        #else
        throw NSError(domain: "LocalClientError", code: 1, userInfo: [NSLocalizedDescriptionKey: "AppKit not available"])
        #endif
    }

    public func listTorrents() async throws -> [TorrentItem] {
        // Local client handoff does not have a queryable daemon RPC
        return []
    }

    public func pauseTorrent(id: String) async throws {}
    public func resumeTorrent(id: String) async throws {}
    public func removeTorrent(id: String, deleteData: Bool) async throws {}
}

