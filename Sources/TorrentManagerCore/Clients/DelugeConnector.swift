import Foundation

public actor DelugeConnector: TorrentClientProtocol {
    public nonisolated let clientType: ClientType = .deluge
    public nonisolated let connectionName: String

    private let endpointURL: URL
    private let password: String
    private let session: URLSession
    private var requestId: Int = 1
    private var isAuthenticated: Bool = false

    public init(
        connectionName: String = "Deluge Web",
        endpointURL: URL,
        password: String,
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            return URLSession(configuration: config)
        }()
    ) {
        self.connectionName = connectionName
        self.endpointURL = endpointURL
        self.password = password
        self.session = session
    }

    public func testConnection() async throws -> ConnectionTestResult {
        do {
            try await authenticate()
            let version = try await getVersion()
            return ConnectionTestResult(isSuccessful: true, serverVersion: version)
        } catch {
            return ConnectionTestResult(isSuccessful: false, errorMessage: error.localizedDescription)
        }
    }

    public func addTorrent(magnetURI: String, options: AddTorrentOptions) async throws -> String {
        try await authenticateIfNeeded()

        var delugeOptions: [String: Any] = [
            "add_paused": options.startPaused
        ]
        if let dir = options.downloadDirectory, !dir.isEmpty {
            delugeOptions["download_location"] = dir
        }

        let params: [Any] = [magnetURI, delugeOptions]
        let response = try await callRPC(method: "core.add_torrent_magnet", params: params)

        if let hash = response["result"] as? String {
            return hash
        } else if let errorDict = response["error"] as? [String: Any], let msg = errorDict["message"] as? String {
            throw NSError(domain: "DelugeError", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return "added"
    }

    public func listTorrents() async throws -> [TorrentItem] {
        try await authenticateIfNeeded()

        let keys = ["name", "total_size", "progress", "download_payload_rate", "upload_payload_rate", "eta", "state", "num_seeds", "num_peers", "total_done"]
        let params: [Any] = [keys, [String: Any]()]

        let response = try await callRPC(method: "web.update_ui", params: params)
        guard let result = response["result"] as? [String: Any],
              let torrents = result["torrents"] as? [String: [String: Any]] else {
            return []
        }

        var items: [TorrentItem] = []
        for (torrentId, dict) in torrents {
            let name = dict["name"] as? String ?? "Unnamed"
            let totalSize = (dict["total_size"] as? NSNumber)?.int64Value ?? 0
            let totalDone = (dict["total_done"] as? NSNumber)?.int64Value ?? 0
            let progressRaw = (dict["progress"] as? NSNumber)?.doubleValue ?? 0.0
            let downSpeed = (dict["download_payload_rate"] as? NSNumber)?.int64Value ?? 0
            let upSpeed = (dict["upload_payload_rate"] as? NSNumber)?.int64Value ?? 0
            let eta = (dict["eta"] as? NSNumber)?.intValue
            let stateStr = (dict["state"] as? String)?.lowercased() ?? "unknown"
            let seeds = (dict["num_seeds"] as? NSNumber)?.intValue ?? 0
            let peers = (dict["num_peers"] as? NSNumber)?.intValue ?? 0

            let state: TorrentTransferState
            switch stateStr {
            case "downloading": state = .downloading
            case "seeding": state = .seeding
            case "paused": state = .paused
            case "queued": state = .queued
            case "checking": state = .checking
            case "error": state = .error
            default: state = .unknown
            }

            items.append(TorrentItem(
                id: torrentId,
                name: name,
                totalSizeBytes: totalSize,
                completedBytes: totalDone,
                progress: progressRaw / 100.0, // Deluge returns 0-100
                downloadSpeedBytesPerSec: downSpeed,
                uploadSpeedBytesPerSec: upSpeed,
                etaSeconds: eta,
                state: state,
                connectedSeeds: seeds,
                connectedLeechers: peers
            ))
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func pauseTorrent(id: String) async throws {
        try await authenticateIfNeeded()
        _ = try await callRPC(method: "core.pause_torrent", params: [[id]])
    }

    public func resumeTorrent(id: String) async throws {
        try await authenticateIfNeeded()
        _ = try await callRPC(method: "core.resume_torrent", params: [[id]])
    }

    public func removeTorrent(id: String, deleteData: Bool) async throws {
        try await authenticateIfNeeded()
        _ = try await callRPC(method: "core.remove_torrent", params: [id, deleteData])
    }

    private func authenticateIfNeeded() async throws {
        if !isAuthenticated {
            try await authenticate()
        }
    }

    private func authenticate() async throws {
        let response = try await callRPC(method: "auth.login", params: [password])
        if let success = response["result"] as? Bool, success {
            isAuthenticated = true
        } else {
            isAuthenticated = false
            throw NSError(domain: "DelugeError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deluge login failed. Check password."])
        }
    }

    private func getVersion() async throws -> String {
        let response = try await callRPC(method: "daemon.get_version", params: [])
        return (response["result"] as? String) ?? "Unknown"
    }

    private func callRPC(method: String, params: [Any]) async throws -> [String: Any] {
        let jsonURL = endpointURL.appendingPathComponent("json")
        var request = URLRequest(url: jsonURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6.0

        let body: [String: Any] = [
            "method": method,
            "params": params,
            "id": requestId
        ]
        requestId += 1

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        return json
    }
}

