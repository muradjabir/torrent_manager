import SwiftUI
import TorrentManagerCore

public struct SearchAndComparisonView: View {
    @ObservedObject var viewModel: TorrentSearchViewModel
    @State private var selectedDetailTab: DetailTab = .indexers

    private enum DetailTab: String, CaseIterable, Identifiable {
        case indexers = "Indexer Sources"
        case trackers = "Synthesized Trackers"
        case client = "Client Status"

        var id: String { rawValue }
    }

    public init(viewModel: TorrentSearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Search Header
            searchHeaderBar

            // 2. Search Status & Sort Bar
            statusAndSortBar

            Divider()

            // 3. Master Releases Table (Top)
            masterResultsTable
                .frame(minHeight: 180, idealHeight: 280)

            Divider()

            // 4. Large Multi-Indexer Comparison Matrix & Inspector (Bottom)
            bottomInspectorMatrix
                .frame(minHeight: 250, idealHeight: 330)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel.rawResults.isEmpty && !viewModel.isSearching {
                Task { await viewModel.performSearch() }
            }
        }
    }

    // MARK: - Search Header Bar
    private var searchHeaderBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search enabled indexers (e.g. Ubuntu, Fedora, Debian, Blender)...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        Task { await viewModel.performSearch() }
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )

            Button(action: {
                Task { await viewModel.performSearch() }
            }) {
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 6)
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                        .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.isSearching)

            // Active client switcher dropdown
            Menu {
                Button("macOS Default App") {
                    Task { await viewModel.setActiveClient(id: "localApp") }
                }

                ForEach(viewModel.clientProfiles) { profile in
                    Button("\(profile.name) (\(profile.host):\(profile.port))") {
                        Task { await viewModel.setActiveClient(id: profile.id.uuidString) }
                    }
                }

                Divider()

                Button("Open Client Web UI / App") {
                    viewModel.openClientWebUIOrApp(id: viewModel.activeProfileId)
                }

                Button("Add Client on Local IP...") {
                    viewModel.isShowingAddClientSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                    Text(viewModel.activeClientDisplayName)
                        .lineLimit(1)
                }
                .font(.caption)
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: 180)

            // Switch to Transfers Dashboard Button
            Button(action: {
                viewModel.appNavigationMode = .downloads
                Task {
                    if viewModel.activeProfileId == "localApp", let firstRemote = viewModel.clientProfiles.first {
                        await viewModel.setActiveClient(id: firstRemote.id.uuidString)
                    }
                    await viewModel.fetchClientTorrents()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Transfers")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Switch to Deluge-style transfers dashboard")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Status & Sorting Bar
    private var statusAndSortBar: some View {
        HStack {
            // Live Search Status
            HStack(spacing: 6) {
                switch viewModel.searchStatus {
                case .idle:
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                case .searching:
                    ProgressView()
                        .controlSize(.mini)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.primary)

                case .found(let count):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Found \(count) release group(s)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                case .empty:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                case .error(let msg):
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Sort Selector
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Sort by:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $viewModel.selectedSort) {
                    ForEach(TorrentSearchViewModel.SortOption.allCases) { opt in
                        HStack {
                            Image(systemName: opt.icon)
                            Text(opt.rawValue)
                        }
                        .tag(opt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Master Results Table (Top View)
    private var masterResultsTable: some View {
        Group {
            if viewModel.isSearching && viewModel.rawResults.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Querying enabled indexers...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sortedResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(["Ubuntu", "Debian", "Fedora", "Linux Mint", "Blender"], id: \.self) { term in
                            Button(term) {
                                viewModel.searchQuery = term
                                Task { await viewModel.performSearch() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.sortedResults, selection: $viewModel.selectedGroupId) {
                    TableColumn("Release Title") { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.canonicalTitle)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("\(group.sources.count) source(s)")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)

                                if !group.sizeConsistentAcrossSources {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                        Text("Size Mismatch")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .width(min: 280, ideal: 380)

                    TableColumn("Size") { group in
                        Text(group.formattedSize)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .width(min: 80, ideal: 95)

                    TableColumn("Seeds") { group in
                        Text("\(group.maxSeeders)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .width(min: 60, ideal: 75)

                    TableColumn("Leech") { group in
                        Text("\(group.maxLeechers)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 55, ideal: 65)

                    TableColumn("Health") { group in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(healthColor(group.consolidatedHealth.statusColor))
                                .frame(width: 8, height: 8)
                            Text("\(Int(group.consolidatedHealth.score))%")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .width(min: 65, ideal: 75)

                    TableColumn("Dispatch") { group in
                        Button(action: {
                            Task { await viewModel.dispatchTorrent(group) }
                        }) {
                            Label("Send", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Send to \(viewModel.activeClientDisplayName)")
                    }
                    .width(min: 65, ideal: 75)
                }
            }
        }
    }

    // MARK: - Large Bottom Inspector View (Full-Width Indexer Comparison Matrix)
    private var bottomInspectorMatrix: some View {
        Group {
            if let group = viewModel.selectedGroup {
                VStack(spacing: 0) {
                    // Header Bar of the Selected Release
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(group.canonicalTitle)
                                    .font(.system(size: 14, weight: .bold))
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(healthColor(group.consolidatedHealth.statusColor))
                                        .frame(width: 8, height: 8)
                                    Text("\(Int(group.consolidatedHealth.score))% Swarm Health")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("(\(group.maxSeeders) seeds / \(group.maxLeechers) leechers)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                            }

                            HStack(spacing: 10) {
                                Text("Hash: \(group.infoHash)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(group.infoHash, forType: .string)
                                    viewModel.dispatchStatus = "Copied info hash!"
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy info hash")
                            }
                        }

                        Spacer()

                        // Action Buttons
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(group.unifiedMagnetURI, forType: .string)
                            viewModel.dispatchStatus = "Copied unified magnet URI to clipboard!"
                        }) {
                            Label("Copy Magnet URI", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button(action: {
                            Task { await viewModel.dispatchTorrent(group) }
                        }) {
                            Label("Send to \(viewModel.activeClientDisplayName)", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                    Divider()

                    // Tab Picker for Details
                    HStack {
                        Picker("", selection: $selectedDetailTab) {
                            Text("📊 Indexer Sources (\(group.sources.count))").tag(DetailTab.indexers)
                            Text("🛰 Synthesized Trackers (\(group.trackers.count))").tag(DetailTab.trackers)
                            Text("💻 Active Client: \(viewModel.activeClientDisplayName)").tag(DetailTab.client)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 540)

                        Spacer()

                        if let status = viewModel.dispatchStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider()

                    // Tab Contents
                    Group {
                        switch selectedDetailTab {
                        case .indexers:
                            indexerComparisonTabView(group: group)
                        case .trackers:
                            trackersTabView(group: group)
                        case .client:
                            clientStatusTabView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a torrent release from the table above to view detailed per-indexer comparison, trackers, and health.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Tab 1: Indexer Comparison View (Full Width Matrix)
    private func indexerComparisonTabView(group: TorrentComparisonGroup) -> some View {
        VStack(spacing: 0) {
            if !group.sizeConsistentAcrossSources {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Size Discrepancy Detected: Reporting indexers provide different file sizes for this hash. Verify contents before downloading.")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                Divider()
            }

            Table(group.sources) {
                TableColumn("Indexer") { source in
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text(source.indexerName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .width(min: 160, ideal: 190)

                TableColumn("Reported Title") { source in
                    Text(source.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .help(source.title)
                }
                .width(min: 260, ideal: 360)

                TableColumn("Reported Size") { source in
                    HStack(spacing: 4) {
                        Text(ByteCountFormatter.string(fromByteCount: source.reportedSizeBytes, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                        if !group.sizeConsistentAcrossSources {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                        }
                    }
                }
                .width(min: 90, ideal: 110)

                TableColumn("Seeds") { source in
                    Text("\(source.reportedSeeders)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
                .width(min: 60, ideal: 75)

                TableColumn("Leech") { source in
                    Text("\(source.reportedLeechers)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .width(min: 55, ideal: 65)

                TableColumn("S/L Ratio") { source in
                    let ratio = source.reportedLeechers > 0 ? Double(source.reportedSeeders) / Double(source.reportedLeechers) : Double(source.reportedSeeders)
                    Text(String(format: "%.1f", ratio))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ratio >= 1.0 ? .green : .orange)
                }
                .width(min: 65, ideal: 75)

                TableColumn("Uploader Status") { source in
                    if source.verifiedUploader {
                        Text("VIP / Trusted")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    } else {
                        Text("Community")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 90, ideal: 105)

                TableColumn("Actions") { source in
                    HStack(spacing: 8) {
                        if let detailURL = source.detailURL {
                            Button(action: {
                                NSWorkspace.shared.open(detailURL)
                            }) {
                                Image(systemName: "safari")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Open on \(source.indexerName) website")
                        }

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(source.magnetURI, forType: .string)
                            viewModel.dispatchStatus = "Copied \(source.indexerName) magnet URI!"
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Copy source magnet URI")
                    }
                }
                .width(min: 65, ideal: 75)
            }
        }
    }

    // MARK: - Tab 2: Trackers View
    private func trackersTabView(group: TorrentComparisonGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Synthesized Announce Trackers (\(group.trackers.count) endpoints)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Copy All Trackers") {
                    let list = group.trackers.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(list, forType: .string)
                    viewModel.dispatchStatus = "Copied all \(group.trackers.count) announce trackers!"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List(group.trackers, id: \.self) { tracker in
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(tracker)
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tracker, forType: .string)
                        viewModel.dispatchStatus = "Copied tracker URL"
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Tab 3: Client Status View
    private func clientStatusTabView() -> some View {
        let activeStatus = viewModel.clientStatuses[viewModel.activeProfileId]
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.activeClientDisplayName)
                            .font(.headline)
                        Text("Target Torrent Client")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.openClientWebUIOrApp(id: viewModel.activeProfileId)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.activeProfileId == "localApp" ? "arrow.up.forward.app" : "safari")
                            Text(viewModel.activeProfileId == "localApp" ? "Launch Client App" : "Open Web UI in Browser")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button(action: {
                        Task { await viewModel.checkClientStatus(id: viewModel.activeProfileId) }
                    }) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Stats Cards
                HStack(spacing: 12) {
                    statusCard(
                        title: "CONNECTION STATUS",
                        value: (activeStatus?.isOnline == true) ? "Online" : ((activeStatus == nil) ? "Checking" : "Offline"),
                        icon: (activeStatus?.isOnline == true) ? "checkmark.circle.fill" : "xmark.circle.fill",
                        color: (activeStatus?.isOnline == true) ? .green : .red,
                        subtitle: activeStatus?.serverVersion ?? (activeStatus?.errorMessage ?? "Connecting...")
                    )

                    statusCard(
                        title: "ACTIVE TORRENTS",
                        value: "\(activeStatus?.torrentCount ?? 0)",
                        icon: "arrow.down.to.line.circle",
                        color: .blue,
                        subtitle: "Loaded in client"
                    )

                    statusCard(
                        title: "DOWNLOAD RATE",
                        value: activeStatus?.formattedDownloadSpeed ?? "0.0 KB/s",
                        icon: "arrow.down.circle.fill",
                        color: .green,
                        subtitle: "Aggregated transfer"
                    )

                    statusCard(
                        title: "UPLOAD RATE",
                        value: activeStatus?.formattedUploadSpeed ?? "0.0 KB/s",
                        icon: "arrow.up.circle.fill",
                        color: .purple,
                        subtitle: "Aggregated transfer"
                    )
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func healthColor(_ colorStr: String) -> Color {
        switch colorStr {
        case "green": return .green
        case "yellow": return .yellow
        default: return .red
        }
    }
}

