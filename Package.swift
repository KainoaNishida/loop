// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Loop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MinderCore",
            targets: ["MinderCore"]
        ),
        .executable(
            name: "Loop",
            targets: ["Loop"]
        )
    ],
    targets: [
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MinderCore",
            dependencies: ["CSQLite"],
            path: "Sources/MinderCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Loop",
            dependencies: ["MinderCore"],
            path: "Sources/MinderApp"
        ),
        .testTarget(
            name: "MinderCoreTests",
            dependencies: ["MinderCore"],
            path: "Tests/MinderCoreTests",
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "MinderAppTests",
            dependencies: ["Loop", "MinderCore"],
            path: "Tests/MinderAppTests"
        )
    ]
)
