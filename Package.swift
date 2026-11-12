// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TorrentManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TorrentManagerCore",
            targets: ["TorrentManagerCore"]
        ),
        .executable(
            name: "TorrentManager",
            targets: ["TorrentManager"]
        ),
    ],
    targets: [
        .target(
            name: "TorrentManagerCore",
            path: "Sources/TorrentManagerCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .executableTarget(
            name: "TorrentManager",
            dependencies: ["TorrentManagerCore"],
            path: "Sources/TorrentManager",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
                ])
            ]
        ),
    ]
)
