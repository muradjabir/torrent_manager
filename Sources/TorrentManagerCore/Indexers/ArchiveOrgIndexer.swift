import Foundation

/// Indexer querying the Internet Archive API.
public actor ArchiveOrgIndexer: TorrentIndexer {
    public nonisolated let id: String = "archive_org"
    public nonisolated let displayName: String = "Internet Archive"
    public nonisolated let capabilities = IndexerCapabilities(
        supportsCategories: true,
        supportsFileDetails: false,
        supportsSorting: true
    )

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(
        query: String,
        category: TorrentCategory?,
        limit: Int = 30
    ) async throws -> [TorrentSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        // Search Internet Archive advanced search API for items with torrent files
        let mediaFilter: String
        switch category {
        case .video: mediaFilter = " AND mediatype:(movies)"
        case .audio: mediaFilter = " AND mediatype:(audio)"
        case .applications: mediaFilter = " AND mediatype:(software)"
        default: mediaFilter = ""
        }

        let searchURLString = "https://archive.org/advancedsearch.php?q=\(encodedQuery)\(mediaFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&fl[]=identifier,title,mediatype,publicdate,downloads,item_size&rows=\(limit)&output=json"

        guard let url = URL(string: searchURLString) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct ArchiveResponse: Codable {
            struct ResponseDoc: Codable {
                let docs: [DocItem]?
            }
            struct DocItem: Codable {
                let identifier: String?
                let title: String?
                let mediatype: String?
                let publicdate: String?
                let downloads: Int?
                let item_size: Int64?
            }
            let response: ResponseDoc?
        }

        guard let parsed = try? JSONDecoder().decode(ArchiveResponse.self, from: data),
              let docs = parsed.response?.docs else {
            return []
        }

        var results: [TorrentSearchResult] = []
        let dateFormatter = ISO8601DateFormatter()

        for doc in docs {
            guard let identifier = doc.identifier, !identifier.isEmpty else { continue }
            let title = doc.title ?? identifier
            let size = doc.item_size ?? 500_000_000
            let dlCount = doc.downloads ?? 10
            let seeders = max(5, dlCount / 20)
            let leechers = max(1, dlCount / 100)

            // Direct torrent URL hosted on Archive.org
            let torrentURL = "https://archive.org/download/\(identifier)/\(identifier)_archive.torrent"
            let fakeHash = String(identifier.sha1Prefix.prefix(40)).lowercased()

            let date = doc.publicdate.flatMap { dateFormatter.date(from: $0) }

            results.append(TorrentSearchResult(
                id: "ia_\(identifier)",
                title: title,
                infoHash: fakeHash,
                sizeBytes: size,
                seeders: seeders,
                leechers: leechers,
                category: category ?? .other,
                uploadDate: date,
                magnetURI: torrentURL,
                indexerId: id,
                indexerName: displayName,
                verifiedUploader: true,
                detailURL: URL(string: "https://archive.org/details/\(identifier)")
            ))
        }

        return results
    }

    public func fetchFiles(id: String, infoHash: String) async throws -> [TorrentFileInfo] {
        return []
    }
}

private extension String {
    var sha1Prefix: String {
        let utf8 = self.utf8
        var hash = ""
        for byte in utf8 {
            hash += String(format: "%02x", byte)
            if hash.count >= 40 { break }
        }
        while hash.count < 40 {
            hash += "0"
        }
        return hash
    }
}

