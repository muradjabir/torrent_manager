import Foundation

public struct ClientProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var type: ClientType
    public var host: String
    public var port: Int
    public var useHTTPS: Bool
    public var username: String
    public var password: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: ClientType,
        host: String,
        port: Int,
        useHTTPS: Bool = false,
        username: String = "",
        password: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.useHTTPS = useHTTPS
        self.username = username
        self.password = password
    }

    public var endpointURL: URL? {
        var cleanHost = host
        if cleanHost.starts(with: "http://") {
            cleanHost = String(cleanHost.dropFirst(7))
        } else if cleanHost.starts(with: "https://") {
            cleanHost = String(cleanHost.dropFirst(8))
        }
        if cleanHost.contains(":") {
            cleanHost = cleanHost.components(separatedBy: ":").first ?? cleanHost
        }
        cleanHost = cleanHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !cleanHost.isEmpty else { return nil }
        let scheme = useHTTPS ? "https" : "http"
        return URL(string: "\(scheme)://\(cleanHost):\(port)")
    }

    public static func defaultPort(for type: ClientType) -> Int {
        switch type {
        case .deluge: return 8112
        case .transmission: return 9091
        case .qbittorrent: return 8080
        case .localApp: return 0
        }
    }
}

