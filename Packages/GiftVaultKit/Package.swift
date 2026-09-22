// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GiftVaultKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GiftVaultKit", targets: ["GiftVaultKit"]),
        .library(name: "GiftVaultStoreKit", targets: ["GiftVaultStoreKit"]),
    ],
    dependencies: [
        // GRDB/SQLite persistence (issue #3). Exact resolution pinned in
        // Package.resolved; Apple platforms link the system SQLite, Linux
        // CI links the system libsqlite3 (libsqlite3-dev installed in the
        // swift image by the CI job).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Pure domain layer: no third-party dependencies, Linux-testable.
        .target(name: "GiftVaultKit"),
        // GRDB persistence layer (issue #3): repositories, migrations,
        // fixtures, backup exclusion.
        .target(
            name: "GiftVaultStoreKit",
            dependencies: [
                "GiftVaultKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "GiftVaultKitTests", dependencies: ["GiftVaultKit"]),
        .testTarget(
            name: "GiftVaultStoreKitTests",
            dependencies: ["GiftVaultStoreKit"]
        ),
    ]
)
