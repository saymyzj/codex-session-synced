// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexSynced",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexSynced", targets: ["CodexSynced"])
    ],
    targets: [
        .target(
            name: "CodexSyncedCore",
            path: "Sources/CodexSyncedCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexSynced",
            dependencies: ["CodexSyncedCore"],
            path: "Sources/CodexSynced"
        ),
        .testTarget(
            name: "CodexSyncedTests",
            dependencies: ["CodexSyncedCore"],
            path: "Tests/CodexSyncedTests"
        )
    ]
)
