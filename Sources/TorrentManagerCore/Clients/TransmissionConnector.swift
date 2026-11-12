import Foundation

public actor TransmissionConnector: TorrentClientProtocol {
    public nonisolated let clientType: ClientType = .transmission
    public nonisolated let connectionName: String

    private let endpointURL: URL
    private let username: String?
    private let password: String?
    private let session: URLSession
    private var sessionId: String?
    private var tagCounter: Int = 1

    public init(
        connectionName: String = "Transmission",
        endpointURL: URL,
        username: String? = nil,
        password: String? = nil,
        session: URLSession = .shared
    ) {
        self.connectionName = connectionName
        self.endpointURL = endpointURL
        self.username = username
        self.password = password
        self.session = session
    }

    public func testConnection() async throws -> ConnectionTestResult {
        do {
            let response = try await callRPC(method: "session-get", arguments: [:])
            if let args = response["arguments"] as? [String: Any],
               let version = args["version"] as? String {
                return ConnectionTestResult(isSuccessful: true, serverVersion: version)
            }
            return ConnectionTestResult(isSuccessful: true, serverVersion: "Connected")
        } catch {
            return ConnectionTestResult(isSuccessful: false, errorMessage: error.localizedDescription)
        }
    }

    public func addTorrent(magnetURI: String, options: AddTorrentOptions) async throws -> String {
        var args: [String: Any] = [
            "filename": magnetURI,
            "paused": options.startPaused
        ]
        if let dir = options.downloadDirectory, !dir.isEmpty {
            args["download-dir"] = dir
        }

        let response = try await callRPC(method: "torrent-add", arguments: args)
        if let result = response["result"] as? String, result == "success" {
            if let args = response["arguments"] as? [String: Any] {
                if let added = args["torrent-added"] as? [String: Any], let id = added["id"] as? Int {
                    return "\(id)"
                } else if let dup = args["torrent-duplicate"] as? [String: Any], let id = dup["id"] as? Int {
                    return "\(id) (duplicate)"
                }
            }
            return "added"
        } else {
            let msg = response["result"] as? String ?? "Unknown error"
            throw NSError(domain: "TransmissionError", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    public func listTorrents() async throws -> [TorrentItem] {
        let fields = ["id", "name", "totalSize", "percentDone", "rateDownload", "rateUpload", "eta", "status", "peersConnected", "peersSendingToUs"]
        let response = try await callRPC(method: "torrent-get", arguments: ["fields": fields])

        guard let args = response["arguments"] as? [String: Any],
              let torrents = args["torrents"] as? [[String: Any]] else {
            return []
        }

        var items: [TorrentItem] = []
        for t in torrents {
            let id = "\(t["id"] as? Int ?? 0)"
            let name = t["name"] as? String ?? "Unnamed"
            let totalSize = (t["totalSize"] as? NSNumber)?.int64Value ?? 0
            let percentDone = (t["percentDone"] as? NSNumber)?.doubleValue ?? 0.0
            let rateDownload = (t["rateDownload"] as? NSNumber)?.int64Value ?? 0
            let rateUpload = (t["rateUpload"] as? NSNumber)?.int64Value ?? 0
            let eta = (t["eta"] as? NSNumber)?.intValue
            let statusCode = t["status"] as? Int ?? 0
            let peers = t["peersConnected"] as? Int ?? 0
            let seeds = t["peersSendingToUs"] as? Int ?? 0

            let state: TorrentTransferState
            switch statusCode {
            case 0: state = .paused
            case 1, 2: state = .checking
            case 3: state = .queued
            case 4: state = .downloading
            case 5: state = .queued
            case 6: state = .seeding
            default: state = .unknown
            }

            items.append(TorrentItem(
                id: id,
                name: name,
                totalSizeBytes: totalSize,
                completedBytes: Int64(Double(totalSize) * percentDone),
                progress: percentDone,
                downloadSpeedBytesPerSec: rateDownload,
                uploadSpeedBytesPerSec: rateUpload,
                etaSeconds: (eta != nil && eta! > 0) ? eta : nil,
                state: state,
                connectedSeeds: seeds,
                connectedLeechers: peers
            ))
        }

        return items
    }

    public func pauseTorrent(id: String) async throws {
        guard let intId = Int(id) else { return }
        _ = try await callRPC(method: "torrent-stop", arguments: ["ids": [intId]])
    }

    public func resumeTorrent(id: String) async throws {
        guard let intId = Int(id) else { return }
        _ = try await callRPC(method: "torrent-start", arguments: ["ids": [intId]])
    }

    public func removeTorrent(id: String, deleteData: Bool) async throws {
        guard let intId = Int(id) else { return }
        _ = try await callRPC(method: "torrent-remove", arguments: [
            "ids": [intId],
            "delete-local-data": deleteData
        ])
    }

    private func callRPC(method: String, arguments: [String: Any]) async throws -> [String: Any] {
        let rpcURL = endpointURL.appendingPathComponent("transmission/rpc")

        for attempt in 0..<2 {
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 6.0

            if let sessionId = sessionId {
                request.setValue(sessionId, forHTTPHeaderField: "X-Transmission-Session-Id")
            }

            if let username = username, let password = password {
                let authStr = "\(username):\(password)"
                if let authData = authStr.data(using: .utf8) {
                    request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
            }

            let payload: [String: Any] = [
                "method": method,
                "arguments": arguments,
                "tag": tagCounter
            ]
            tagCounter += 1

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            // CSRF Handshake
            if httpResponse.statusCode == 409 {
                if let newSessionId = httpResponse.allHeaderFields["X-Transmission-Session-Id"] as? String ??
                    httpResponse.allHeaderFields["x-transmission-session-id"] as? String {
                    self.sessionId = newSessionId
                    if attempt == 0 {
                        continue // Retry with the new session ID
                    }
                }
                throw NSError(domain: "TransmissionError", code: 409, userInfo: [NSLocalizedDescriptionKey: "Transmission 409 session handshake failed"])
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            return json
        }

        throw NSError(domain: "TransmissionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed after CSRF handshake retry"])
    }
}

