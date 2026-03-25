// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bear-mcp",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "bear-mcp",
            targets: ["BearMCPCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1"),
    ],
    targets: [
        .target(
            name: "BearCore"
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
    ]
)
