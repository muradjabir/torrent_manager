import Foundation
import SwiftUI
import AppKit
import TorrentManagerCore

@MainActor
public final class TorrentSearchViewModel: ObservableObject {
    public enum SortOption: String, CaseIterable, Identifiable {
        case seedersDesc = "Seeds (High to Low)"
        case seedersAsc = "Seeds (Low to High)"
        case nameAsc = "Name (A to Z)"
        case nameDesc = "Name (Z to A)"
        case sizeDesc = "Size (Largest)"
        case sizeAsc = "Size (Smallest)"
        case healthDesc = "Swarm Health"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .seedersDesc, .seedersAsc: return "arrow.up.arrow.down.circle"
            case .nameAsc, .nameDesc: return "textformat.abc"
            case .sizeDesc, .sizeAsc: return "internaldrive"
            case .healthDesc: return "heart.fill"
            }
        }
    }

    public enum AppNavigationMode: String, CaseIterable, Identifiable {
        case search = "Search Indexers"
        case downloads = "Client Downloads"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .downloads: return "arrow.down.circle.fill"
            }
        }
    }

    public enum SearchStatus: Equatable {
        case idle
        case searching(query: String)
        case found(count: Int)
        case empty(query: String)
        case error(message: String)
    }

    @Published public var searchQuery: String = "linux"
    @Published public var selectedCategory: TorrentCategory = .all
    @Published public var selectedSort: SortOption = .seedersDesc
    @Published public var isSearching: Bool = false
    @Published public var rawResults: [TorrentComparisonGroup] = []
    @Published public var selectedGroupId: String?
    @Published public var statusMessage: String = "Ready to search"
    @Published public var searchStatus: SearchStatus = .idle

    // Indexer management (pluggable architecture)
    @Published public var indexerProfiles: [IndexerProfile] = []
    @Published public var isShowingAddIndexerSheet: Bool = false

    // Client profiles and connections
    @Published public var clientProfiles: [ClientProfile] = []
    @Published public var activeProfileId: String = "localApp"
    @Published public var clientStatuses: [String: ClientStatusInfo] = [:]
    @Published public var isCheckingClientStatus: Bool = false
    @Published public var dispatchStatus: String?
    @Published public var isShowingAddClientSheet: Bool = false

    // Live Client Torrents (Deluge-style downloads view)
    @Published public var appNavigationMode: AppNavigationMode = .search
    @Published public var activeClientTorrents: [TorrentItem] = []
    @Published public var selectedClientTorrentId: String? = nil
    @Published public var torrentStateFilter: TorrentTransferState? = nil
    @Published public var torrentSearchFilter: String = ""
    @Published public var isLoadingTorrents: Bool = false
    @Published public var clientActionStatus: String? = nil

    private let indexerManager: IndexerManager
    private let clientManager: ClientManager

    public init() {
        self.indexerManager = IndexerManager()
        self.clientManager = ClientManager()

        if CommandLine.arguments.contains("--downloads") {
            self.appNavigationMode = .downloads
        }

        Task {
            await self.loadIndexers()
            await self.loadClientProfiles()
            await self.performSearch()
            if self.appNavigationMode == .downloads {
                await self.fetchClientTorrents()
            }
        }
    }

    public var sortedResults: [TorrentComparisonGroup] {
        switch selectedSort {
        case .seedersDesc:
            return rawResults.sorted { $0.maxSeeders > $1.maxSeeders }
        case .seedersAsc:
            return rawResults.sorted { $0.maxSeeders < $1.maxSeeders }
        case .nameAsc:
            return rawResults.sorted { $0.canonicalTitle.localizedCaseInsensitiveCompare($1.canonicalTitle) == .orderedAscending }
        case .nameDesc:
            return rawResults.sorted { $0.canonicalTitle.localizedCaseInsensitiveCompare($1.canonicalTitle) == .orderedDescending }
        case .sizeDesc:
            return rawResults.sorted { $0.sizeBytes > $1.sizeBytes }
        case .sizeAsc:
            return rawResults.sorted { $0.sizeBytes < $1.sizeBytes }
        case .healthDesc:
            return rawResults.sorted { $0.consolidatedHealth.score > $1.consolidatedHealth.score }
        }
    }

    public var selectedGroup: TorrentComparisonGroup? {
        sortedResults.first(where: { $0.id == selectedGroupId })
    }

    public var activeClientDisplayName: String {
        if activeProfileId == "localApp" {
            return "macOS Default App"
        }
        if let profile = clientProfiles.first(where: { $0.id.uuidString == activeProfileId }) {
            return profile.name
        }
        return "macOS Default App"
    }

    // MARK: - Indexer Operations
    public func loadIndexers() async {
        self.indexerProfiles = await indexerManager.getProfiles()
    }

    public func addIndexerProfile(_ profile: IndexerProfile) async {
        await indexerManager.addOrUpdateProfile(profile)
        await loadIndexers()
        await performSearch()
    }

    public func removeIndexerProfile(id: UUID) async {
        await indexerManager.removeProfile(id: id)
        await loadIndexers()
        await performSearch()
    }

    public func toggleIndexer(id: UUID) async {
        await indexerManager.toggleIndexer(id: id)
        await loadIndexers()
        await performSearch()
    }

    // MARK: - Client Operations
    public func loadClientProfiles() async {
        self.clientProfiles = await clientManager.getProfiles()
        self.activeProfileId = await clientManager.getActiveProfileId()
        if self.appNavigationMode == .downloads && self.activeProfileId == "localApp", let firstRemote = clientProfiles.first {
            self.activeProfileId = firstRemote.id.uuidString
        }
        await refreshClientStatuses()
        await fetchClientTorrents()
    }

    public func addClientProfile(_ profile: ClientProfile) async {
        await clientManager.addOrUpdateProfile(profile)
        await clientManager.setActiveProfileId(profile.id.uuidString)
        await loadClientProfiles()
        dispatchStatus = "Added \(profile.name) as active client"
        await checkClientStatus(id: profile.id.uuidString)
    }

    public func removeClientProfile(id: UUID) async {
        await clientManager.removeProfile(id: id)
        clientStatuses.removeValue(forKey: id.uuidString)
        await loadClientProfiles()
    }

    public func setActiveClient(id: String) async {
        await clientManager.setActiveProfileId(id)
        self.activeProfileId = id
        await checkClientStatus(id: id)
        await fetchClientTorrents()
    }

    // MARK: - Deluge / Client Transfers Management
    public var filteredClientTorrents: [TorrentItem] {
        var items = activeClientTorrents
        if let filter = torrentStateFilter {
            items = items.filter { $0.state == filter }
        }
        let q = torrentSearchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter { $0.name.lowercased().contains(q) }
        }
        return items
    }

    public var selectedClientTorrent: TorrentItem? {
        activeClientTorrents.first(where: { $0.id == selectedClientTorrentId })
    }

    public func fetchClientTorrents() async {
        guard activeProfileId != "localApp" else {
            activeClientTorrents = []
            return
        }
        isLoadingTorrents = true
        do {
            let items = try await clientManager.listTorrents(targetProfileId: activeProfileId)
            self.activeClientTorrents = items
            if selectedClientTorrentId == nil || !items.contains(where: { $0.id == selectedClientTorrentId }) {
                self.selectedClientTorrentId = items.first?.id
            }
            clientActionStatus = "Fetched \(items.count) torrent(s) from \(activeClientDisplayName)"
        } catch {
            clientActionStatus = "Connection error: \(error.localizedDescription)"
        }
        isLoadingTorrents = false
    }

    public func pauseTorrent(id: String) async {
        do {
            try await clientManager.pauseTorrent(id: id, targetProfileId: activeProfileId)
            clientActionStatus = "Paused torrent"
            await fetchClientTorrents()
        } catch {
            clientActionStatus = "Error pausing: \(error.localizedDescription)"
        }
    }

    public func resumeTorrent(id: String) async {
        do {
            try await clientManager.resumeTorrent(id: id, targetProfileId: activeProfileId)
            clientActionStatus = "Resumed torrent"
            await fetchClientTorrents()
        } catch {
            clientActionStatus = "Error resuming: \(error.localizedDescription)"
        }
    }

    public func removeTorrent(id: String, deleteData: Bool) async {
        do {
            try await clientManager.removeTorrent(id: id, deleteData: deleteData, targetProfileId: activeProfileId)
            clientActionStatus = deleteData ? "Removed torrent & deleted local data" : "Removed torrent from client"
            await fetchClientTorrents()
        } catch {
            clientActionStatus = "Error removing: \(error.localizedDescription)"
        }
    }

    public func refreshClientStatuses() async {
        isCheckingClientStatus = true
        // Check active client first
        let activeStatus = await clientManager.fetchStatusForId(activeProfileId)
        clientStatuses[activeProfileId] = activeStatus

        // Check others concurrently
        for profile in clientProfiles {
            let pid = profile.id.uuidString
            let status = await clientManager.fetchStatus(for: profile)
            clientStatuses[pid] = status
        }
        isCheckingClientStatus = false
    }

    public func checkClientStatus(id: String) async {
        let status = await clientManager.fetchStatusForId(id)
        clientStatuses[id] = status
    }

    public func openClientWebUIOrApp(id: String) {
        if id == "localApp" {
            // Launch default torrent app
            if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000")!) {
                NSWorkspace.shared.openApplication(at: defaultAppURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                dispatchStatus = "Launched \(defaultAppURL.deletingPathExtension().lastPathComponent)"
            } else if let transmissionURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.m0k.transmission") {
                NSWorkspace.shared.openApplication(at: transmissionURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                dispatchStatus = "Launched Transmission"
            } else {
                dispatchStatus = "No default torrent client configured in macOS"
            }
            return
        }

        guard let profile = clientProfiles.first(where: { $0.id.uuidString == id }),
              let url = profile.endpointURL else {
            dispatchStatus = "Unable to construct Web UI URL for client"
            return
        }

        NSWorkspace.shared.open(url)
        dispatchStatus = "Opened \(profile.name) Web UI at \(url.absoluteString)"
    }

    // MARK: - Search Execution
    public func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            statusMessage = "Please enter a search keyword"
            searchStatus = .idle
            return
        }

        let activeIndexers = await indexerManager.getActiveIndexers()
        guard !activeIndexers.isEmpty else {
            statusMessage = "No indexers enabled. Enable or add an indexer in the sidebar."
            searchStatus = .empty(query: query)
            rawResults = []
            return
        }

        isSearching = true
        searchStatus = .searching(query: query)
        let indexerNames = activeIndexers.map(\.displayName).joined(separator: ", ")
        statusMessage = "Searching \(activeIndexers.count) provider(s) (\(indexerNames))..."

        let coordinator = SearchCoordinator(indexers: activeIndexers)
        let outcome = await coordinator.searchWithOutcome(query: query, category: selectedCategory, limitPerIndexer: 30)

        self.rawResults = outcome.groups
        self.isSearching = false

        if outcome.groups.isEmpty {
            if !outcome.errors.isEmpty {
                let errText = outcome.errors.joined(separator: "; ")
                self.searchStatus = .error(message: errText)
                self.statusMessage = "Indexer error: \(errText)"
            } else {
                self.searchStatus = .empty(query: query)
                self.statusMessage = "No results found for \"\(query)\"."
            }
        } else {
            self.searchStatus = .found(count: outcome.groups.count)
            self.statusMessage = "Found \(outcome.groups.count) release group(s)"
            if selectedGroupId == nil || !outcome.groups.contains(where: { $0.id == selectedGroupId }) {
                self.selectedGroupId = outcome.groups.first?.id
            }
        }
    }

    public func dispatchTorrent(_ group: TorrentComparisonGroup) async {
        do {
            dispatchStatus = "Dispatching to \(activeClientDisplayName)..."
            let res = try await clientManager.dispatchTorrent(
                magnetURI: group.unifiedMagnetURI,
                targetProfileId: activeProfileId
            )
            dispatchStatus = "Success: \(res)"
        } catch {
            dispatchStatus = "Error sending to \(activeClientDisplayName): \(error.localizedDescription)"
        }
    }
}
