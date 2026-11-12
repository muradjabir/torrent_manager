import Foundation

public actor QBittorrentConnector: TorrentClientProtocol {
    public nonisolated let clientType: ClientType = .qbittorrent
    public nonisolated let connectionName: String

    private let endpointURL: URL
    private let username: String
    private let password: String
    private let session: URLSession
    private var isAuthenticated: Bool = false

    public init(
        connectionName: String = "qBittorrent Web",
        endpointURL: URL,
        username: String = "admin",
        password: String = "adminadmin",
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            return URLSession(configuration: config)
        }()
    ) {
        self.connectionName = connectionName
        self.endpointURL = endpointURL
        self.username = username
        self.password = password
        self.session = session
    }

    public func testConnection() async throws -> ConnectionTestResult {
        do {
            try await authenticate()
            let version = try await getAppVersion()
            return ConnectionTestResult(isSuccessful: true, serverVersion: version)
        } catch {
            return ConnectionTestResult(isSuccessful: false, errorMessage: error.localizedDescription)
        }
    }

    public func addTorrent(magnetURI: String, options: AddTorrentOptions) async throws -> String {
        try await authenticateIfNeeded()

        let addURL = endpointURL.appendingPathComponent("api/v2/torrents/add")
        var request = URLRequest(url: addURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0

        var params: [String: String] = [
            "urls": magnetURI,
            "paused": options.startPaused ? "true" : "false"
        ]
        if let dir = options.downloadDirectory, !dir.isEmpty {
            params["savepath"] = dir
        }
        if !options.tags.isEmpty {
            params["tags"] = options.tags.joined(separator: ",")
        }

        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        if responseBody.lowercased().contains("fails") {
            throw NSError(domain: "qBittorrentError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to add torrent: \(responseBody)"])
        }

        return "added"
    }

    public func listTorrents() async throws -> [TorrentItem] {
        try await authenticateIfNeeded()

        let listURL = endpointURL.appendingPathComponent("api/v2/torrents/info")
        var request = URLRequest(url: listURL)
        request.timeoutInterval = 6.0

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct QBitTorrentItem: Codable {
            let hash: String
            let name: String
            let size: Int64
            let completed: Int64
            let progress: Double
            let dlspeed: Int64
            let upspeed: Int64
            let eta: Int
            let state: String
            let num_seeds: Int
            let num_leechs: Int
        }

        let items = try JSONDecoder().decode([QBitTorrentItem].self, from: data)

        return items.map { q in
            let state: TorrentTransferState
            switch q.state.lowercased() {
            case "downloading", "forceddl": state = .downloading
            case "uploading", "forcedup", "stalledup": state = .seeding
            case "pauseddl", "pausedup": state = .paused
            case "queueddl", "queuedup": state = .queued
            case "checkingdl", "checkingup", "checkingresume": state = .checking
            case "error", "missingfiles": state = .error
            default: state = .unknown
            }

            return TorrentItem(
                id: q.hash,
                name: q.name,
                totalSizeBytes: q.size,
                completedBytes: q.completed,
                progress: q.progress,
                downloadSpeedBytesPerSec: q.dlspeed,
                uploadSpeedBytesPerSec: q.upspeed,
                etaSeconds: (q.eta > 0 && q.eta < 8640000) ? q.eta : nil,
                state: state,
                connectedSeeds: q.num_seeds,
                connectedLeechers: q.num_leechs
            )
        }
    }

    public func pauseTorrent(id: String) async throws {
        try await authenticateIfNeeded()
        try await postCommand(endpoint: "api/v2/torrents/pause", params: ["hashes": id])
    }

    public func resumeTorrent(id: String) async throws {
        try await authenticateIfNeeded()
        try await postCommand(endpoint: "api/v2/torrents/resume", params: ["hashes": id])
    }

    public func removeTorrent(id: String, deleteData: Bool) async throws {
        try await authenticateIfNeeded()
        try await postCommand(endpoint: "api/v2/torrents/delete", params: [
            "hashes": id,
            "deleteFiles": deleteData ? "true" : "false"
        ])
    }

    private func authenticateIfNeeded() async throws {
        if !isAuthenticated {
            try await authenticate()
        }
    }

    private func authenticate() async throws {
        let loginURL = endpointURL.appendingPathComponent("api/v2/auth/login")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        if httpResponse.statusCode == 200 && (bodyStr.lowercased().contains("ok") || bodyStr.isEmpty) {
            isAuthenticated = true
        } else {
            isAuthenticated = false
            throw NSError(domain: "qBittorrentError", code: 401, userInfo: [NSLocalizedDescriptionKey: "qBittorrent login failed."])
        }
    }

    private func getAppVersion() async throws -> String {
        let versionURL = endpointURL.appendingPathComponent("api/v2/app/version")
        let (data, response) = try await session.data(from: versionURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return "Connected"
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Connected"
    }

    private func postCommand(endpoint: String, params: [String: String]) async throws {
        let url = endpointURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

