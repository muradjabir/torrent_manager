import Foundation

public actor TorznabIndexer: TorrentIndexer {
    public nonisolated let id: String
    public nonisolated let displayName: String
    public nonisolated let capabilities = IndexerCapabilities(
        supportsCategories: true,
        supportsFileDetails: false,
        supportsSorting: true
    )

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(
        id: String = "torznab_indexer",
        displayName: String = "Torznab (Jackett/Prowlarr)",
        baseURL: URL,
        apiKey: String,
        session: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func search(
        query: String,
        category: TorrentCategory?,
        limit: Int = 50
    ) async throws -> [TorrentSearchResult] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api"), resolvingAgainstBaseURL: true) else {
            return []
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "o", value: "json"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cat = category, let catCode = mapCategory(cat) {
            queryItems.append(URLQueryItem(name: "cat", value: catCode))
        }

        components.queryItems = queryItems
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try parseTorznabJSON(data: data)
    }

    public func fetchFiles(id: String, infoHash: String) async throws -> [TorrentFileInfo] {
        return []
    }

    private func parseTorznabJSON(data: Data) throws -> [TorrentSearchResult] {
        struct TorznabResponse: Codable {
            struct Channel: Codable {
                struct Item: Codable {
                    let title: String
                    let link: String?
                    let pubDate: String?
                    let size: String?
                    let comments: String?
                    let enclosure: Enclosure?
                    let torznabAttrs: [TorznabAttr]?

                    struct Enclosure: Codable {
                        let url: String?
                        let length: String?
                    }

                    struct TorznabAttr: Codable {
                        let name: String
                        let value: String
                    }

                    enum CodingKeys: String, CodingKey {
                        case title, link, pubDate, size, comments, enclosure
                        case torznabAttrs = "attr"
                    }
                }
                let item: [Item]?
            }
            let channel: Channel?
        }

        guard let json = try? JSONDecoder().decode(TorznabResponse.self, from: data),
              let items = json.channel?.item else {
            return []
        }

        var results: [TorrentSearchResult] = []
        let dateFormatter = ISO8601DateFormatter()

        for item in items {
            var seeders = 0
            var leechers = 0
            var infoHash = ""
            var magnetURI = ""

            if let attrs = item.torznabAttrs {
                for attr in attrs {
                    switch attr.name {
                    case "seeders": seeders = Int(attr.value) ?? 0
                    case "peers": leechers = Int(attr.value) ?? 0
                    case "infohash": infoHash = attr.value
                    case "magneturl": magnetURI = attr.value
                    default: break
                    }
                }
            }

            if magnetURI.isEmpty, let link = item.link, link.starts(with: "magnet:") {
                magnetURI = link
            }

            if infoHash.isEmpty, let hashFromMagnet = extractInfoHash(from: magnetURI) {
                infoHash = hashFromMagnet
            }

            guard !infoHash.isEmpty else { continue }

            let size = Int64(item.size ?? item.enclosure?.length ?? "0") ?? 0
            let date = item.pubDate.flatMap { dateFormatter.date(from: $0) }

            results.append(TorrentSearchResult(
                id: "\(id)_\(infoHash)",
                title: item.title,
                infoHash: infoHash,
                sizeBytes: size,
                seeders: seeders,
                leechers: leechers,
                category: .all,
                uploadDate: date,
                magnetURI: magnetURI.isEmpty ? "magnet:?xt=urn:btih:\(infoHash)&dn=\(item.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")" : magnetURI,
                indexerId: id,
                indexerName: displayName,
                detailURL: item.comments.flatMap { URL(string: $0) }
            ))
        }

        return results
    }

    private func extractInfoHash(from magnetURI: String) -> String? {
        guard let url = URL(string: magnetURI),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let xt = components.queryItems?.first(where: { $0.name == "xt" })?.value else {
            return nil
        }
        return xt.replacingOccurrences(of: "urn:btih:", with: "").lowercased()
    }

    private func mapCategory(_ category: TorrentCategory) -> String? {
        switch category {
        case .all: return nil
        case .video: return "2000"
        case .audio: return "3000"
        case .applications: return "4000"
        case .games: return "1000"
        case .other: return "7000"
        }
    }
}

