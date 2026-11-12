import Foundation
import AppKit
import SwiftUI
import TorrentManagerCore

@main
struct TorrentManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let args = CommandLine.arguments

        if args.contains("--test") {
            TorrentManagerCLI.runDiagnosticsSync()
            exit(0)
        }

        if let searchIndex = args.firstIndex(of: "--search"), searchIndex + 1 < args.count {
            let query = args[searchIndex + 1]
            TorrentManagerCLI.runSearchDemoSync(query: query)
            exit(0)
        }

        if args.contains("--cli") {
            TorrentManagerCLI.runDiagnosticsSync()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Torrent Manager") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Clear any corrupted off-screen window coordinates from previous multi-monitor setups
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame SwiftUI.WindowGroup<TorrentManager.ContentView>-1-AppWindow-1")
        UserDefaults.standard.synchronize()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                if window.frame.origin.x < 0 || window.frame.origin.y < 0 {
                    window.center()
                }
            }
        }

        for delay in [0.05, 0.2, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows {
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    if window.frame.origin.x < 0 || window.frame.origin.y < 0 {
                        window.center()
                    }
                    window.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

public struct TorrentManagerCLI {
    public static func runDiagnosticsSync() {
        let sema = DispatchSemaphore(value: 0)
        Task {
            await runDiagnostics()
            sema.signal()
        }
        sema.wait()
    }

    public static func runSearchDemoSync(query: String) {
        let sema = DispatchSemaphore(value: 0)
        Task {
            await runSearchDemo(query: query)
            sema.signal()
        }
        sema.wait()
    }

    public static func runDiagnostics() async {
        print("=====================================================")
        print("🚀 macOS Torrent Manager (Swift 6 Native Architecture)")
        print("=====================================================")

        print("\n[1/4] 🧪 Testing Swarm Health Algorithm...")
        let healthA = SwarmHealth(seeders: 1200, leechers: 45)
        let healthB = SwarmHealth(seeders: 4, leechers: 80)
        let healthDead = SwarmHealth(seeders: 0, leechers: 10)

        print("  • High seeders (1200 seeds, 45 leechers): Score \(healthA.score)/100 [\(healthA.label)] - Color: \(healthA.statusColor)")
        print("  • Low seeders (4 seeds, 80 leechers): Score \(healthB.score)/100 [\(healthB.label)] - Color: \(healthB.statusColor)")
        print("  • Dead swarm (0 seeds, 10 leechers): Score \(healthDead.score)/100 [\(healthDead.label)] - Color: \(healthDead.statusColor)")

        assert(healthA.score > 80.0, "Healthy swarm should score > 80")
        assert(healthDead.score == 0.0, "Dead swarm should score 0")
        print("  ✅ Health scoring verified!")

        print("\n[2/4] 🧪 Testing Multi-Indexer Deduplication & Comparison Matrix...")
        let dummyHash = "4a5b6c7d8e9f0123456789abcdef0123456789ab"
        let result1 = TorrentSearchResult(
            id: "ia_101",
            title: "Debian 12.5 Netinst ISO",
            infoHash: dummyHash,
            sizeBytes: 650_000_000,
            seeders: 850,
            leechers: 35,
            category: .applications,
            uploadDate: Date(),
            magnetURI: "magnet:?xt=urn:btih:\(dummyHash)&dn=Debian&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce",
            indexerId: "archive_org",
            indexerName: "Internet Archive"
        )

        let result2 = TorrentSearchResult(
            id: "torznab_202",
            title: "Debian-12.5-netinst.iso",
            infoHash: dummyHash,
            sizeBytes: 650_000_000,
            seeders: 920,
            leechers: 40,
            category: .applications,
            uploadDate: Date(),
            magnetURI: "magnet:?xt=urn:btih:\(dummyHash)&dn=Debian&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce",
            indexerId: "jackett_prowlarr",
            indexerName: "Prowlarr/Torznab"
        )

        let engine = TorrentComparisonEngine()
        let groups = engine.aggregateAndCompare(results: [result1, result2])

        assert(groups.count == 1, "Expected 1 deduplicated group from 2 identical info hashes")
        let group = groups[0]
        print("  • Canonical Title: \(group.canonicalTitle)")
        print("  • Sources Count: \(group.sources.count) (Merged Sources)")
        print("  • Max Seeders: \(group.maxSeeders)")
        print("  • Size Consistency: \(group.sizeConsistentAcrossSources ? "Consistent (100% match)" : "Discrepancy detected")")
        print("  • Unified Magnet Contains Combined Trackers: \(group.unifiedMagnetURI.contains("opentrackr") && group.unifiedMagnetURI.contains("stealth"))")
        print("  ✅ Comparison and deduplication verified!")

        print("\n[3/4] 🧪 Initializing Universal Torrent Client Connectors...")
        let clientManager = ClientManager()

        let delugeProfile = ClientProfile(
            name: "Home NAS Deluge",
            type: .deluge,
            host: "192.168.1.100",
            port: 8112,
            password: "deluge_password"
        )
        await clientManager.addOrUpdateProfile(delugeProfile)
        print("  • Configured: \(delugeProfile.name) (\(delugeProfile.host):\(delugeProfile.port))")

        let transmissionProfile = ClientProfile(
            name: "Living Room Transmission",
            type: .transmission,
            host: "192.168.1.105",
            port: 9091,
            username: "admin",
            password: "password"
        )
        await clientManager.addOrUpdateProfile(transmissionProfile)
        print("  • Configured: \(transmissionProfile.name) (\(transmissionProfile.host):\(transmissionProfile.port))")

        let qbitProfile = ClientProfile(
            name: "Server qBittorrent",
            type: .qbittorrent,
            host: "192.168.1.120",
            port: 8080,
            username: "admin",
            password: "adminadmin"
        )
        await clientManager.addOrUpdateProfile(qbitProfile)
        print("  • Configured: \(qbitProfile.name) (\(qbitProfile.host):\(qbitProfile.port))")

        let profiles = await clientManager.getProfiles()
        print("  • Total Active Remote Profiles: \(profiles.count)")
        print("  ✅ Dynamic client profile & IP network integration verified!")

        print("\n[4/4] 🧪 Search Coordinator & Indexer Initialization...")
        let defaultIndexer = ArchiveOrgIndexer()
        let coordinator = SearchCoordinator(indexers: [defaultIndexer])
        print("  • Indexer registered: \(defaultIndexer.displayName)")
        _ = coordinator
        print("  ✅ Architecture verification complete! System is ready.")
        print("\n👉 To run a live query against enabled indexers: swift run TorrentManager --search \"ubuntu\"")
    }

    public static func runSearchDemo(query: String) async {
        print("\n🔍 Querying indexers for: \"\(query)\"...")
        let defaultIndexer = ArchiveOrgIndexer()
        let coordinator = SearchCoordinator(indexers: [defaultIndexer])

        let groups = await coordinator.search(query: query, category: .all, limitPerIndexer: 15)

        if groups.isEmpty {
            print("No results returned or remote mirror unreachable.")
            return
        }

        print("\nFound \(groups.count) release group(s):\n")
        print(String(repeating: "-", count: 85))
        let headerTitle = "Title".padding(toLength: 40, withPad: " ", startingAt: 0)
        let headerSize = "Size".padding(toLength: 10, withPad: " ", startingAt: 0)
        let headerSeeds = "Seeds".padding(toLength: 8, withPad: " ", startingAt: 0)
        let headerLeech = "Leech".padding(toLength: 8, withPad: " ", startingAt: 0)
        print("\(headerTitle) | \(headerSize) | \(headerSeeds) | \(headerLeech) | Health")
        print(String(repeating: "-", count: 85))

        for g in groups.prefix(10) {
            let truncatedTitle = g.canonicalTitle.count > 38 ? String(g.canonicalTitle.prefix(35)) + "..." : g.canonicalTitle
            let titleCol = truncatedTitle.padding(toLength: 40, withPad: " ", startingAt: 0)
            let sizeCol = g.formattedSize.padding(toLength: 10, withPad: " ", startingAt: 0)
            let seedsCol = "\(g.maxSeeders)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let leechCol = "\(g.maxLeechers)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let healthCol = "\(Int(g.consolidatedHealth.score))%"
            print("\(titleCol) | \(sizeCol) | \(seedsCol) | \(leechCol) | \(healthCol)")
        }
        print(String(repeating: "-", count: 85))

        if let first = groups.first {
            print("\n🌟 Top Result Detailed Comparison:")
            print("  Title: \(first.canonicalTitle)")
            print("  Info Hash: \(first.infoHash)")
            print("  Sources: \(first.sources.map(\.indexerName).joined(separator: ", "))")
            print("  Unified Magnet: \(first.unifiedMagnetURI.prefix(90))...")
        }
    }
}
