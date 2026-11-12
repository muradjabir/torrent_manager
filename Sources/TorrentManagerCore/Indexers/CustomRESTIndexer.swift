import Foundation

public actor CustomRESTIndexer: TorrentIndexer {
    public nonisolated let id: String
    public nonisolated let displayName: String
    public nonisolated let capabilities = IndexerCapabilities(
        supportsCategories: true,
        supportsFileDetails: true,
        supportsSorting: false
    )

    private let session: URLSession
    private let baseURL: URL

    public static let standardTrackers: [String] = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://tracker.bittor.pw:1337/announce",
        "udp://public.popcorn-tracker.org:6969/announce",
        "udp://tracker.dler.org:6969/announce",
        "udp://exodus.desync.com:6969",
        "udp://open.demonii.com:1337/announce",
        "udp://tracker.openbittorrent.com:6969/announce"
    ]

    public init(
        id: String = "custom_rest",
        displayName: String = "Custom API Indexer",
        baseURL: URL,
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 15.0
            config.waitsForConnectivity = true
            return URLSession(configuration: config)
        }()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.session = session
    }

    public func search(
        query: String,
        category: TorrentCategory?,
        limit: Int = 50
    ) async throws -> [TorrentSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let catCode = mapCategory(category)
        let endpoint = "q.php?q=\(encodedQuery)&cat=\(catCode)"

        let data = try await performRequest(path: endpoint)

        // Parse JSON leniently
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var results: [TorrentSearchResult] = []

        for item in jsonArray {
            let itemId = stringValue(item["id"])
            let hash = stringValue(item["info_hash"])

            // Sentinel "No results" response
            if itemId == "0" || hash.lowercased() == "0000000000000000000000000000000000000000" {
                continue
            }

            let name = stringValue(item["name"])
            guard !name.isEmpty, !hash.isEmpty else { continue }

            let seeders = intValue(item["seeders"])
            let leechers = intValue(item["leechers"])
            let size = int64Value(item["size"])
            let addedRaw = doubleValue(item["added"])
            let uploadDate = addedRaw > 0 ? Date(timeIntervalSince1970: addedRaw) : nil

            let status = stringValue(item["status"]).lowercased()
            let isVerified = (status == "vip" || status == "trusted")

            let magnetURI = Self.buildMagnetURI(
                infoHash: hash,
                name: name,
                trackers: Self.standardTrackers
            )

            let rawCategory = stringValue(item["category"])
            let resolvedCat = mapNumericCategory(rawCategory)

            let detailURL = URL(string: "description.php?id=\(itemId)", relativeTo: baseURL)

            let result = TorrentSearchResult(
                id: "\(id)_\(itemId)",
                title: name,
                infoHash: hash,
                sizeBytes: size,
                seeders: seeders,
                leechers: leechers,
                category: resolvedCat,
                uploadDate: uploadDate,
                magnetURI: magnetURI,
                indexerId: id,
                indexerName: displayName,
                verifiedUploader: isVerified,
                detailURL: detailURL
            )

            results.append(result)
            if results.count >= limit {
                break
            }
        }

        return results
    }

    public func fetchFiles(id: String, infoHash: String) async throws -> [TorrentFileInfo] {
        let cleanId = id.replacingOccurrences(of: "\(self.id)_", with: "")
        let endpoint = "f.php?id=\(cleanId)"

        let data = try await performRequest(path: endpoint)
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var fileList: [TorrentFileInfo] = []
        for (index, file) in jsonArray.enumerated() {
            let nameList = file["name"] as? [String] ?? []
            let sizeList = file["size"] as? [String] ?? []

            let fileName = nameList.first ?? "File \(index + 1)"
            let fileSize = Int64(sizeList.first ?? "0") ?? 0
            fileList.append(TorrentFileInfo(id: "\(cleanId)_\(index)", name: fileName, sizeBytes: fileSize))
        }

        return fileList
    }

    public static func buildMagnetURI(infoHash: String, name: String, trackers: [String]) -> String {
        var components = URLComponents()
        components.scheme = "magnet"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "xt", value: "urn:btih:\(infoHash.uppercased())"),
            URLQueryItem(name: "dn", value: name)
        ]

        for tracker in trackers {
            queryItems.append(URLQueryItem(name: "tr", value: tracker))
        }

        components.queryItems = queryItems
        return components.string ?? "magnet:?xt=urn:btih:\(infoHash)"
    }

    private func performRequest(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        var lastError: Error?
        for _ in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                // Verify that response is actually JSON, not HTML redirect/challenge
                guard let firstByte = data.first, (firstByte == 0x5B || firstByte == 0x7B) else {
                    throw URLError(.cannotParseResponse)
                }

                return data
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s pause before retry
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    // Helper functions for lenient decoding of heterogeneous types
    private func stringValue(_ val: Any?) -> String {
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        return ""
    }

    private func intValue(_ val: Any?) -> Int {
        if let i = val as? Int { return i }
        if let s = val as? String, let i = Int(s) { return i }
        if let n = val as? NSNumber { return n.intValue }
        return 0
    }

    private func int64Value(_ val: Any?) -> Int64 {
        if let i = val as? Int64 { return i }
        if let s = val as? String, let i = Int64(s) { return i }
        if let n = val as? NSNumber { return n.int64Value }
        return 0
    }

    private func doubleValue(_ val: Any?) -> Double {
        if let d = val as? Double { return d }
        if let s = val as? String, let d = Double(s) { return d }
        if let n = val as? NSNumber { return n.doubleValue }
        return 0
    }

    private func mapCategory(_ category: TorrentCategory?) -> String {
        guard let category else { return "0" }
        switch category {
        case .all: return "0"
        case .video: return "200"
        case .audio: return "100"
        case .applications: return "300"
        case .games: return "400"
        case .other: return "600"
        }
    }

    private func mapNumericCategory(_ raw: String?) -> TorrentCategory {
        guard let raw, let prefix = raw.first else { return .other }
        switch prefix {
        case "1": return .audio
        case "2": return .video
        case "3": return .applications
        case "4": return .games
        default: return .other
        }
    }
}
