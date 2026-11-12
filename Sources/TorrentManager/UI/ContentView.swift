import SwiftUI
import AppKit
import TorrentManagerCore

public struct ContentView: View {
    @StateObject private var viewModel = TorrentSearchViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            if viewModel.appNavigationMode == .search {
                SearchAndComparisonView(viewModel: viewModel)
            } else {
                ClientDownloadsView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 1060, minHeight: 700)
        .sheet(isPresented: $viewModel.isShowingAddClientSheet) {
            AddClientSheet { newProfile in
                Task {
                    await viewModel.addClientProfile(newProfile)
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddIndexerSheet) {
            AddIndexerSheet { newIndexer in
                Task {
                    await viewModel.addIndexerProfile(newIndexer)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // View Mode Switcher
                Picker("", selection: $viewModel.appNavigationMode) {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(TorrentSearchViewModel.AppNavigationMode.search)
                    Label("Transfers", systemImage: "arrow.down.circle.fill")
                        .tag(TorrentSearchViewModel.AppNavigationMode.downloads)
                }
                .pickerStyle(.segmented)
                .help("Toggle between Search & Indexers and Client Downloads")

                Spacer()

                // Add Indexer button
                Button(action: {
                    viewModel.isShowingAddIndexerSheet = true
                }) {
                    Label("Add Indexer", systemImage: "globe.badge.chevron.backward")
                }
                .help("Add custom indexer feed")

                // Add Client button
                Button(action: {
                    viewModel.isShowingAddClientSheet = true
                }) {
                    Label("Add Client", systemImage: "server.rack")
                }
                .help("Add torrent client on local IP")

                // Open Web UI / Launch App button
                Button(action: {
                    viewModel.openClientWebUIOrApp(id: viewModel.activeProfileId)
                }) {
                    Label("Open Web UI", systemImage: "safari")
                }
                .help("Open Web UI in browser or launch app")
            }
        }
        .onAppear {
            Task {
                await viewModel.loadIndexers()
                await viewModel.loadClientProfiles()
                await viewModel.performSearch()
            }
        }
    }
}
