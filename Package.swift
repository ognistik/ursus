// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ursus",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "BearApplication",
            targets: ["BearApplication"]
        ),
        .executable(
            name: "ursus",
            targets: ["BearMCPCLI"]
        ),
        .executable(
            name: "ursus-helper",
            targets: ["BearSelectedNoteHelper"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.97.0"),
    ],
    targets: [
        .target(
            name: "BearCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "BearDB",
            dependencies: [
                "BearCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "BearXCallback",
            dependencies: [
                "BearCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "BearApplication",
            dependencies: [
                "BearCore",
                "BearDB",
                "BearXCallback",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "BearMCP",
            dependencies: [
                "BearCore",
                "BearApplication",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .executableTarget(
            name: "BearMCPCLI",
            dependencies: [
                "BearApplication",
                "BearMCP",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "BearSelectedNoteHelper",
            dependencies: [
                "BearXCallback",
            ]
        ),
        .testTarget(
            name: "BearCoreTests",
            dependencies: [
                "BearCore",
                "BearXCallback",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "BearApplicationTests",
            dependencies: [
                "BearApplication",
                "BearCore",
                "BearDB",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "BearMCPTests",
            dependencies: [
                "BearMCP",
                "BearCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "BearMCPCLITests",
            dependencies: [
                "BearMCPCLI",
                "BearCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
