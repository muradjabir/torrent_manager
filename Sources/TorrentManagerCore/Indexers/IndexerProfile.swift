import Foundation

public enum IndexerType: String, Codable, Sendable, CaseIterable {
    case customAPI = "customAPI"
    case torznab = "torznab"
    case archiveOrg = "archiveOrg"

    public var displayName: String {
        switch self {
        case .customAPI: return "Custom REST API Provider"
        case .torznab: return "Torznab Feed (Jackett / Prowlarr)"
        case .archiveOrg: return "Internet Archive"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let val = IndexerType(rawValue: raw) {
            self = val
        } else {
            self = .customAPI
        }
    }
}

public struct IndexerProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var type: IndexerType
    public var endpointURLString: String
    public var apiKey: String
    public var isEnabled: Bool
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        type: IndexerType,
        endpointURLString: String,
        apiKey: String = "",
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpointURLString = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    public var endpointURL: URL? {
        var str = endpointURLString
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://\(str)"
        }
        return URL(string: str)
    }
}

