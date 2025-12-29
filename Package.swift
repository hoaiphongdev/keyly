// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Keyly",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "Keyly",
            path: "Sources/Keyly",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
