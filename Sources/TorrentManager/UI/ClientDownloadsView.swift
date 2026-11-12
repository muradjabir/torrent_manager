import SwiftUI
import AppKit
import TorrentManagerCore

public struct ClientDownloadsView: View {
    @ObservedObject var viewModel: TorrentSearchViewModel
    @State private var showingDeleteConfirmation: Bool = false
    @State private var deleteWithData: Bool = false
    @State private var selectedDetailTab: BottomTab = .status

    private enum BottomTab: String, CaseIterable, Identifiable {
        case status = "Status & Transfer"
        case details = "Details & Hash"

        var id: String { rawValue }
    }

    public init(viewModel: TorrentSearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Deluge-style Control Bar
            controlToolbarView

            Divider()

            // 2. Main Torrents Table on top, Details Notebook on bottom (Full Width)
            VStack(spacing: 0) {
                torrentsTableView
                    .frame(minHeight: 220, idealHeight: 340)

                Divider()

                torrentDetailNotebookView
                    .frame(minHeight: 200, idealHeight: 260)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                await viewModel.fetchClientTorrents()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .confirmationDialog(
            "Remove Torrent",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Client", role: .destructive) {
                if let id = viewModel.selectedClientTorrentId {
                    Task { await viewModel.removeTorrent(id: id, deleteData: false) }
                }
            }
            Button("Remove & Delete Downloaded Files", role: .destructive) {
                if let id = viewModel.selectedClientTorrentId {
                    Task { await viewModel.removeTorrent(id: id, deleteData: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \"\(viewModel.selectedClientTorrent?.name ?? "this torrent")\"?")
        }
    }

    // MARK: - Control Toolbar
    private var controlToolbarView: some View {
        HStack(spacing: 12) {
            // Client Selector Dropdown
            Menu {
                ForEach(viewModel.clientProfiles) { profile in
                    Button("\(profile.name) (\(profile.host):\(profile.port))") {
                        Task { await viewModel.setActiveClient(id: profile.id.uuidString) }
                    }
                }
                Divider()
                Button("macOS Default App") {
                    Task { await viewModel.setActiveClient(id: "localApp") }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                    Text(viewModel.activeClientDisplayName)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: 220)

            // Client Online Status Badge
            let activeStatus = viewModel.clientStatuses[viewModel.activeProfileId]
            HStack(spacing: 5) {
                Circle()
                    .fill(activeStatus?.isOnline == true ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(activeStatus?.isOnline == true ? (activeStatus?.serverVersion ?? "Online") : "Offline")
                    .font(.caption)
                    .foregroundColor(activeStatus?.isOnline == true ? .primary : .red)
            }

            Divider()
                .frame(height: 18)

            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    if let id = viewModel.selectedClientTorrentId {
                        Task { await viewModel.resumeTorrent(id: id) }
                    }
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Resume selected torrent")
                .disabled(viewModel.selectedClientTorrentId == nil)

                Button(action: {
                    if let id = viewModel.selectedClientTorrentId {
                        Task { await viewModel.pauseTorrent(id: id) }
                    }
                }) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Pause selected torrent")
                .disabled(viewModel.selectedClientTorrentId == nil)

                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove selected torrent")
                .disabled(viewModel.selectedClientTorrentId == nil)

                Button(action: {
                    Task {
                        await viewModel.fetchClientTorrents()
                        await viewModel.checkClientStatus(id: viewModel.activeProfileId)
                    }
                }) {
                    if viewModel.isLoadingTorrents {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh torrent list from client")
            }

            // Quick Filter by name
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter downloads...", text: $viewModel.torrentSearchFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !viewModel.torrentSearchFilter.isEmpty {
                    Button(action: { viewModel.torrentSearchFilter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 220)

            Spacer()

            // Aggregate Transfer Speeds Indicator
            if let st = activeStatus, st.isOnline {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text(st.formattedDownloadSpeed)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.blue)
                            .font(.caption2)
                        Text(st.formattedUploadSpeed)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "tray.2.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text("\(viewModel.activeClientTorrents.count) torrents")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }

            // Launch Web UI / App button
            Button(action: {
                viewModel.openClientWebUIOrApp(id: viewModel.activeProfileId)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.activeProfileId == "localApp" ? "arrow.up.forward.app" : "safari")
                    Text(viewModel.activeProfileId == "localApp" ? "Launch App" : "Open Web UI")
                }
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            // Switch to Search Indexers button
            Button(action: {
                viewModel.appNavigationMode = .search
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Indexers")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Switch to Multi-Indexer Search & Comparison")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Main Deluge-style Downloads Table
    private var torrentsTableView: some View {
        Group {
            if viewModel.activeProfileId == "localApp" {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("macOS Default App Connected")
                        .font(.headline)
                    Text("The default macOS magnet handler passes magnet links directly to your desktop torrent client. To view live transfer stats, configure a Deluge, Transmission, or qBittorrent profile.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    Button("Open Client Web UI / App") {
                        viewModel.openClientWebUIOrApp(id: "localApp")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoadingTorrents && viewModel.activeClientTorrents.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching torrent list from \(viewModel.activeClientDisplayName)...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredClientTorrents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Torrents Loaded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("No active torrents match the selected filter in \(viewModel.activeClientDisplayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Refresh Client") {
                        Task { await viewModel.fetchClientTorrents() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.filteredClientTorrents, selection: $viewModel.selectedClientTorrentId) {
                    TableColumn("Name") { torrent in
                        HStack(spacing: 8) {
                            Image(systemName: torrent.state.iconName)
                                .foregroundColor(colorForState(torrent.state))
                                .font(.system(size: 13))
                            Text(torrent.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .width(min: 240, ideal: 340)

                    TableColumn("Size") { torrent in
                        Text(torrent.formattedSize)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .width(min: 80, ideal: 95)

                    TableColumn("Progress") { torrent in
                        VStack(alignment: .leading, spacing: 3) {
                            ProgressView(value: torrent.progress, total: 1.0)
                                .tint(colorForState(torrent.state))
                            HStack {
                                Text(torrent.formattedProgress)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                Spacer()
                                Text(torrent.formattedCompleted)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("State") { torrent in
                        Text(torrent.state.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorForState(torrent.state))
                    }
                    .width(min: 85, ideal: 100)

                    TableColumn("Down Speed") { torrent in
                        Text(torrent.downloadSpeedBytesPerSec > 0 ? torrent.formattedDownSpeed : "—")
                            .font(.system(size: 12, weight: torrent.downloadSpeedBytesPerSec > 0 ? .bold : .regular, design: .monospaced))
                            .foregroundColor(torrent.downloadSpeedBytesPerSec > 0 ? .green : .secondary)
                    }
                    .width(min: 85, ideal: 105)

                    TableColumn("Up Speed") { torrent in
                        Text(torrent.uploadSpeedBytesPerSec > 0 ? torrent.formattedUpSpeed : "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(torrent.uploadSpeedBytesPerSec > 0 ? .blue : .secondary)
                    }
                    .width(min: 80, ideal: 95)

                    TableColumn("ETA") { torrent in
                        Text(torrent.formattedETA)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 65, ideal: 80)

                    TableColumn("Seeds") { torrent in
                        Text("\(torrent.connectedSeeds)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .width(min: 55, ideal: 65)

                    TableColumn("Peers") { torrent in
                        Text("\(torrent.connectedLeechers)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 55, ideal: 65)
                }
                .contextMenu {
                    if let selected = viewModel.selectedClientTorrent {
                        if selected.state == .paused {
                            Button("Resume") {
                                Task { await viewModel.resumeTorrent(id: selected.id) }
                            }
                        } else {
                            Button("Pause") {
                                Task { await viewModel.pauseTorrent(id: selected.id) }
                            }
                        }
                        Divider()
                        Button("Remove from Client", role: .destructive) {
                            Task { await viewModel.removeTorrent(id: selected.id, deleteData: false) }
                        }
                        Button("Remove & Delete Files", role: .destructive) {
                            Task { await viewModel.removeTorrent(id: selected.id, deleteData: true) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Details Notebook (Deluge style)
    private var torrentDetailNotebookView: some View {
        Group {
            if let torrent = viewModel.selectedClientTorrent {
                VStack(spacing: 0) {
                    // Header Bar of the Selected Torrent
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: torrent.state.iconName)
                            .foregroundColor(colorForState(torrent.state))
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(torrent.name)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            Text("ID: \(torrent.id)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Quick Actions
                        HStack(spacing: 8) {
                            if torrent.state == .paused {
                                Button(action: {
                                    Task { await viewModel.resumeTorrent(id: torrent.id) }
                                }) {
                                    Label("Resume", systemImage: "play.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button(action: {
                                    Task { await viewModel.pauseTorrent(id: torrent.id) }
                                }) {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button(role: .destructive, action: {
                                showingDeleteConfirmation = true
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

                    Divider()

                    // Notebook Tab Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Transfer & Storage Grid
                            HStack(spacing: 12) {
                                detailInfoBox(
                                    title: "DOWNLOADED",
                                    value: "\(torrent.formattedCompleted) / \(torrent.formattedSize)",
                                    subtitle: torrent.formattedProgress
                                )

                                detailInfoBox(
                                    title: "DOWNLOAD SPEED",
                                    value: torrent.formattedDownSpeed,
                                    subtitle: "ETA: \(torrent.formattedETA)"
                                )

                                detailInfoBox(
                                    title: "UPLOAD SPEED",
                                    value: torrent.formattedUpSpeed,
                                    subtitle: "Connected: \(torrent.connectedLeechers) peers"
                                )

                                detailInfoBox(
                                    title: "SWARM SEEDS",
                                    value: "\(torrent.connectedSeeds)",
                                    subtitle: "Active seeders"
                                )
                            }

                            // Progress Bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Overall Progress: \(torrent.formattedProgress)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("Status: \(torrent.state.displayName)")
                                        .font(.caption)
                                        .foregroundColor(colorForState(torrent.state))
                                }
                                ProgressView(value: torrent.progress, total: 1.0)
                                    .tint(colorForState(torrent.state))
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .padding(14)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.up.circle")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Select a torrent in the table above to view detailed transfer metrics, speeds, and controls.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func detailInfoBox(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func colorForState(_ state: TorrentTransferState) -> Color {
        switch state {
        case .downloading: return .green
        case .seeding: return .blue
        case .paused: return .orange
        case .queued: return .secondary
        case .checking: return .purple
        case .error: return .red
        case .unknown: return .secondary
        }
    }
}
