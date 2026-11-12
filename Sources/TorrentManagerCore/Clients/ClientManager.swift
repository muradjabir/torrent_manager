import Foundation

public actor ClientManager {
    private var profiles: [ClientProfile]
    private var connectors: [String: any TorrentClientProtocol]
    private var activeProfileId: String
    private static let storageKey = "saved_torrent_client_profiles"

    public init() {
        let localConnector = LocalClientConnector()
        var initialConnectors: [String: any TorrentClientProtocol] = ["localApp": localConnector]
        var initialProfiles: [ClientProfile] = []

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ClientProfile].self, from: data) {
            initialProfiles = saved
            for profile in saved {
                if let connector = Self.makeConnector(for: profile) {
                    initialConnectors[profile.id.uuidString] = connector
                }
            }
        }

        self.connectors = initialConnectors
        self.profiles = initialProfiles
        self.activeProfileId = "localApp"
    }

    public func getProfiles() -> [ClientProfile] {
        return profiles
    }

    public func getActiveProfileId() -> String {
        return activeProfileId
    }

    public func setActiveProfileId(_ id: String) {
        activeProfileId = id
    }

    public func addOrUpdateProfile(_ profile: ClientProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }

        if let connector = Self.makeConnector(for: profile) {
            connectors[profile.id.uuidString] = connector
        }

        saveProfiles()
    }

    public func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        connectors.removeValue(forKey: id.uuidString)
        if activeProfileId == id.uuidString {
            activeProfileId = "localApp"
        }
        saveProfiles()
    }

    public func testProfileConnection(_ profile: ClientProfile) async -> ConnectionTestResult {
        if profile.type == .localApp {
            return ConnectionTestResult(isSuccessful: true, serverVersion: "macOS Default App")
        }

        guard let connector = Self.makeConnector(for: profile) else {
            return ConnectionTestResult(isSuccessful: false, errorMessage: "Invalid Host or Port configuration.")
        }

        do {
            return try await connector.testConnection()
        } catch {
            return ConnectionTestResult(isSuccessful: false, errorMessage: error.localizedDescription)
        }
    }

    public func fetchStatus(for profile: ClientProfile) async -> ClientStatusInfo {
        if profile.type == .localApp {
            return ClientStatusInfo(isOnline: true, serverVersion: "macOS Default Client")
        }

        guard let connector = Self.makeConnector(for: profile) else {
            return ClientStatusInfo(isOnline: false, errorMessage: "Invalid Host or Port")
        }

        do {
            let test = try await connector.testConnection()
            guard test.isSuccessful else {
                return ClientStatusInfo(isOnline: false, errorMessage: test.errorMessage ?? "Connection failed")
            }

            var count = 0
            var totalDown: Int64 = 0
            var totalUp: Int64 = 0
            if let torrents = try? await connector.listTorrents() {
                count = torrents.count
                totalDown = torrents.reduce(0) { $0 + $1.downloadSpeedBytesPerSec }
                totalUp = torrents.reduce(0) { $0 + $1.uploadSpeedBytesPerSec }
            }

            return ClientStatusInfo(
                isOnline: true,
                serverVersion: test.serverVersion,
                torrentCount: count,
                downloadRateBytesPerSec: totalDown,
                uploadRateBytesPerSec: totalUp,
                errorMessage: nil,
                lastChecked: Date()
            )
        } catch {
            return ClientStatusInfo(isOnline: false, errorMessage: error.localizedDescription)
        }
    }

    public func fetchStatusForId(_ id: String) async -> ClientStatusInfo {
        if id == "localApp" {
            return ClientStatusInfo(isOnline: true, serverVersion: "macOS Default Client")
        }
        guard let profile = profiles.first(where: { $0.id.uuidString == id }) else {
            return ClientStatusInfo(isOnline: false, errorMessage: "Client not found")
        }
        return await fetchStatus(for: profile)
    }

    private func getConnector(for targetProfileId: String?) -> any TorrentClientProtocol {
        let keyToUse = targetProfileId ?? activeProfileId
        if keyToUse == "localApp" {
            return connectors["localApp"] ?? LocalClientConnector()
        } else if let conn = connectors[keyToUse] {
            return conn
        } else if let profile = profiles.first(where: { $0.id.uuidString == keyToUse }), let conn = Self.makeConnector(for: profile) {
            connectors[keyToUse] = conn
            return conn
        } else {
            return LocalClientConnector()
        }
    }

    public func listTorrents(targetProfileId: String? = nil) async throws -> [TorrentItem] {
        let connector = getConnector(for: targetProfileId)
        return try await connector.listTorrents()
    }

    public func pauseTorrent(id: String, targetProfileId: String? = nil) async throws {
        let connector = getConnector(for: targetProfileId)
        try await connector.pauseTorrent(id: id)
    }

    public func resumeTorrent(id: String, targetProfileId: String? = nil) async throws {
        let connector = getConnector(for: targetProfileId)
        try await connector.resumeTorrent(id: id)
    }

    public func removeTorrent(id: String, deleteData: Bool, targetProfileId: String? = nil) async throws {
        let connector = getConnector(for: targetProfileId)
        try await connector.removeTorrent(id: id, deleteData: deleteData)
    }

    public func dispatchTorrent(magnetURI: String, options: AddTorrentOptions = AddTorrentOptions(), targetProfileId: String? = nil) async throws -> String {
        let connector = getConnector(for: targetProfileId)
        return try await connector.addTorrent(magnetURI: magnetURI, options: options)
    }

    public static func makeConnector(for profile: ClientProfile) -> (any TorrentClientProtocol)? {
        guard let url = profile.endpointURL else { return nil }

        switch profile.type {
        case .deluge:
            return DelugeConnector(
                connectionName: profile.name,
                endpointURL: url,
                password: profile.password
            )
        case .transmission:
            return TransmissionConnector(
                connectionName: profile.name,
                endpointURL: url,
                username: profile.username.isEmpty ? nil : profile.username,
                password: profile.password.isEmpty ? nil : profile.password
            )
        case .qbittorrent:
            return QBittorrentConnector(
                connectionName: profile.name,
                endpointURL: url,
                username: profile.username.isEmpty ? "admin" : profile.username,
                password: profile.password.isEmpty ? "adminadmin" : profile.password
            )
        case .localApp:
            return LocalClientConnector()
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
