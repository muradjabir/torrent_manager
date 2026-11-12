import Foundation

public actor IndexerManager {
    private var profiles: [IndexerProfile]
    private static let storageKey = "saved_custom_torrent_indexers"

    public init() {
        var initialProfiles: [IndexerProfile] = []

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([IndexerProfile].self, from: data) {
            initialProfiles = saved.map { profile in
                var p = profile
                if p.type == .archiveOrg {
                    p.name = "Internet Archive"
                }
                return p
            }
        } else {
            // Default built-in indexer
            initialProfiles = [
                IndexerProfile(
                    name: "Internet Archive",
                    type: .archiveOrg,
                    endpointURLString: "https://archive.org",
                    isEnabled: true,
                    isBuiltIn: true
                )
            ]
        }

        self.profiles = initialProfiles
    }

    public func getProfiles() -> [IndexerProfile] {
        return profiles
    }

    public func addOrUpdateProfile(_ profile: IndexerProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    public func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }

    public func toggleIndexer(id: UUID) {
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            profiles[idx].isEnabled.toggle()
            save()
        }
    }

    public func getActiveIndexers() -> [any TorrentIndexer] {
        var active: [any TorrentIndexer] = []
        for profile in profiles where profile.isEnabled {
            if let indexer = makeIndexer(for: profile) {
                active.append(indexer)
            }
        }
        return active
    }

    public func makeIndexer(for profile: IndexerProfile) -> (any TorrentIndexer)? {
        guard let url = profile.endpointURL else { return nil }

        switch profile.type {
        case .archiveOrg:
            return ArchiveOrgIndexer()
        case .customAPI:
            return CustomRESTIndexer(
                id: profile.id.uuidString,
                displayName: profile.name,
                baseURL: url
            )
        case .torznab:
            return TorznabIndexer(
                id: profile.id.uuidString,
                displayName: profile.name,
                baseURL: url,
                apiKey: profile.apiKey
            )
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

