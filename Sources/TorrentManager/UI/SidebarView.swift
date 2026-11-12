import SwiftUI
import TorrentManagerCore

public struct SidebarView: View {
    @ObservedObject var viewModel: TorrentSearchViewModel

    public init(viewModel: TorrentSearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App Branding & Navigation Switcher
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Torrent Manager")
                        .font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Primary Mode Switcher (Search vs Transfers)
                Picker("", selection: $viewModel.appNavigationMode) {
                    ForEach(TorrentSearchViewModel.AppNavigationMode.allCases) { mode in
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 10)
                .onChange(of: viewModel.appNavigationMode) { _, newMode in
                    if newMode == .downloads {
                        Task {
                            if viewModel.activeProfileId == "localApp", let firstRemote = viewModel.clientProfiles.first {
                                await viewModel.setActiveClient(id: firstRemote.id.uuidString)
                            }
                            await viewModel.fetchClientTorrents()
                        }
                    }
                }
            }
            .padding(.bottom, 8)

            Divider()

            // Scrollable Contextual Sections
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.appNavigationMode == .search {
                        searchContextSection
                    } else {
                        transfersContextSection
                    }
                }
                .padding(.vertical, 10)
            }

            Divider()

            // Pinned Active Client Footer
            activeClientFooterView
        }
        .frame(minWidth: 240, idealWidth: 270, maxWidth: 310)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Search Mode Context Sections (Categories & Indexers)
    private var searchContextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Categories
            VStack(alignment: .leading, spacing: 3) {
                Text("CATEGORIES")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)

                ForEach(TorrentCategory.allCases, id: \.self) { cat in
                    Button(action: {
                        viewModel.selectedCategory = cat
                        Task { await viewModel.performSearch() }
                    }) {
                        HStack(spacing: 8) {
                            categoryIcon(for: cat)
                                .foregroundColor(viewModel.selectedCategory == cat ? .blue : .primary)
                                .frame(width: 18)
                            Text(cat.displayName)
                                .font(.system(size: 12, weight: viewModel.selectedCategory == cat ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(viewModel.selectedCategory == cat ? Color.blue.opacity(0.12) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
            }

            Divider()
                .padding(.horizontal, 10)

            // Indexers & Feeds
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("INDEXERS & FEEDS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        viewModel.isShowingAddIndexerSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Add custom indexer feed")
                }
                .padding(.horizontal, 14)

                VStack(spacing: 4) {
                    ForEach(viewModel.indexerProfiles) { indexer in
                        indexerRow(indexer: indexer)
                    }

                    Button(action: {
                        viewModel.isShowingAddIndexerSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Custom Indexer...")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private func indexerRow(indexer: IndexerProfile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundColor(indexer.isEnabled ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(indexer.name)
                    .font(.system(size: 12, weight: indexer.isEnabled ? .medium : .regular))
                    .foregroundColor(indexer.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(indexer.endpointURLString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { indexer.isEnabled },
                set: { _ in Task { await viewModel.toggleIndexer(id: indexer.id) } }
            ))
            .toggleStyle(.switch)
            .tint(.green)
            .controlSize(.mini)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
        .contextMenu {
            if !indexer.isBuiltIn {
                Button(role: .destructive, action: {
                    Task { await viewModel.removeIndexerProfile(id: indexer.id) }
                }) {
                    Label("Delete Indexer", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Transfers Mode Context Sections (States & Clients)
    private var transfersContextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Deluge State Filters
            VStack(alignment: .leading, spacing: 3) {
                Text("STATES")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)

                VStack(spacing: 2) {
                    transferStateRow(
                        title: "All",
                        icon: "tray.full.fill",
                        color: .primary,
                        count: viewModel.activeClientTorrents.count,
                        isSelected: viewModel.torrentStateFilter == nil,
                        onSelect: { viewModel.torrentStateFilter = nil }
                    )

                    transferStateRow(
                        title: "Downloading",
                        icon: "arrow.down.circle.fill",
                        color: .green,
                        count: viewModel.activeClientTorrents.filter { $0.state == .downloading }.count,
                        isSelected: viewModel.torrentStateFilter == .downloading,
                        onSelect: { viewModel.torrentStateFilter = .downloading }
                    )

                    transferStateRow(
                        title: "Seeding",
                        icon: "arrow.up.circle.fill",
                        color: .blue,
                        count: viewModel.activeClientTorrents.filter { $0.state == .seeding }.count,
                        isSelected: viewModel.torrentStateFilter == .seeding,
                        onSelect: { viewModel.torrentStateFilter = .seeding }
                    )

                    transferStateRow(
                        title: "Paused",
                        icon: "pause.circle.fill",
                        color: .orange,
                        count: viewModel.activeClientTorrents.filter { $0.state == .paused }.count,
                        isSelected: viewModel.torrentStateFilter == .paused,
                        onSelect: { viewModel.torrentStateFilter = .paused }
                    )

                    transferStateRow(
                        title: "Checking",
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        color: .purple,
                        count: viewModel.activeClientTorrents.filter { $0.state == .checking }.count,
                        isSelected: viewModel.torrentStateFilter == .checking,
                        onSelect: { viewModel.torrentStateFilter = .checking }
                    )

                    transferStateRow(
                        title: "Error",
                        icon: "exclamationmark.circle.fill",
                        color: .red,
                        count: viewModel.activeClientTorrents.filter { $0.state == .error }.count,
                        isSelected: viewModel.torrentStateFilter == .error,
                        onSelect: { viewModel.torrentStateFilter = .error }
                    )
                }
                .padding(.horizontal, 6)
            }

            Divider()
                .padding(.horizontal, 10)

            // Torrent Clients
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TORRENT CLIENTS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        Task {
                            await viewModel.refreshClientStatuses()
                            await viewModel.fetchClientTorrents()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh clients")

                    Button(action: {
                        viewModel.isShowingAddClientSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Add new client")
                }
                .padding(.horizontal, 14)

                VStack(spacing: 4) {
                    clientRow(
                        id: "localApp",
                        name: "macOS Default App",
                        subtitle: "System magnet handler",
                        icon: "laptopcomputer",
                        isActive: viewModel.activeProfileId == "localApp",
                        status: viewModel.clientStatuses["localApp"],
                        endpointURL: nil,
                        canDelete: false
                    )

                    ForEach(viewModel.clientProfiles) { profile in
                        clientRow(
                            id: profile.id.uuidString,
                            name: profile.name,
                            subtitle: "\(profile.host):\(profile.port)",
                            icon: clientIcon(for: profile.type),
                            isActive: viewModel.activeProfileId == profile.id.uuidString,
                            status: viewModel.clientStatuses[profile.id.uuidString],
                            endpointURL: profile.endpointURL,
                            canDelete: true,
                            onDelete: {
                                Task { await viewModel.removeClientProfile(id: profile.id) }
                            }
                        )
                    }

                    Button(action: {
                        viewModel.isShowingAddClientSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Client on Local IP...")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private func transferStateRow(
        title: String,
        icon: String,
        color: Color,
        count: Int,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func clientRow(
        id: String,
        name: String,
        subtitle: String,
        icon: String,
        isActive: Bool,
        status: ClientStatusInfo?,
        endpointURL: URL?,
        canDelete: Bool,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    await viewModel.setActiveClient(id: id)
                    if viewModel.appNavigationMode == .downloads {
                        await viewModel.fetchClientTorrents()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(isActive ? .blue : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .lineLimit(1)

                            if let st = status {
                                Circle()
                                    .fill(st.isOnline ? Color.green : Color.red)
                                    .frame(width: 7, height: 7)
                            }
                        }

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let st = status {
                            if st.isOnline {
                                HStack(spacing: 4) {
                                    Text(st.serverVersion ?? "Online")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    if st.torrentCount > 0 {
                                        Text("• \(st.torrentCount) torrents")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    if st.downloadRateBytesPerSec > 0 {
                                        Text("• ↓\(st.formattedDownloadSpeed)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                    }
                                }
                            } else if let err = st.errorMessage {
                                Text(err)
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Direct in-app transfers jump button
            if id != "localApp" {
                Button(action: {
                    Task {
                        await viewModel.setActiveClient(id: id)
                        viewModel.appNavigationMode = .downloads
                        await viewModel.fetchClientTorrents()
                    }
                }) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12))
                        .foregroundColor(isActive && viewModel.appNavigationMode == .downloads ? .blue : .secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("View live transfers in app")
            }

            // Launch App / Open Web UI button
            Button(action: {
                viewModel.openClientWebUIOrApp(id: id)
            }) {
                Image(systemName: id == "localApp" ? "arrow.up.forward.app" : "safari")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(id == "localApp" ? "Launch macOS Default Torrent App" : "Open Web UI in browser")

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isActive ? Color.blue.opacity(0.12) : Color.clear)
        .cornerRadius(6)
        .contextMenu {
            Button(action: {
                Task {
                    await viewModel.setActiveClient(id: id)
                    viewModel.appNavigationMode = .downloads
                    await viewModel.fetchClientTorrents()
                }
            }) {
                Label("View Live Downloads in App", systemImage: "arrow.down.circle")
            }

            Button(action: {
                viewModel.openClientWebUIOrApp(id: id)
            }) {
                Label(id == "localApp" ? "Launch App" : "Open Web UI in Browser", systemImage: id == "localApp" ? "arrow.up.forward.app" : "safari")
            }

            Button(action: {
                Task { await viewModel.checkClientStatus(id: id) }
            }) {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }

            Divider()

            if canDelete {
                Button(role: .destructive, action: {
                    onDelete?()
                }) {
                    Label("Delete Client", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Pinned Footer
    private var activeClientFooterView: some View {
        HStack(spacing: 8) {
            let activeStatus = viewModel.clientStatuses[viewModel.activeProfileId]
            Circle()
                .fill(activeStatus?.isOnline == true ? Color.green : (activeStatus == nil ? Color.orange : Color.red))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.activeClientDisplayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(activeStatus?.isOnline == true ? (activeStatus?.serverVersion ?? "Online") : (activeStatus?.errorMessage ?? "Ready"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                viewModel.openClientWebUIOrApp(id: viewModel.activeProfileId)
            }) {
                Image(systemName: viewModel.activeProfileId == "localApp" ? "arrow.up.forward.app" : "safari")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Web UI or App")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func categoryIcon(for cat: TorrentCategory) -> Image {
        switch cat {
        case .all: return Image(systemName: "tray.full")
        case .video: return Image(systemName: "film")
        case .audio: return Image(systemName: "music.note")
        case .applications: return Image(systemName: "app")
        case .games: return Image(systemName: "gamecontroller")
        case .other: return Image(systemName: "folder")
        }
    }

    private func clientIcon(for type: ClientType) -> String {
        switch type {
        case .deluge: return "drop.fill"
        case .transmission: return "car.circle.fill"
        case .qbittorrent: return "arrow.down.circle.fill"
        case .localApp: return "laptopcomputer"
        }
    }
}

