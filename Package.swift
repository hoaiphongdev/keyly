// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Keyly",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Keyly",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Keyly",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Find Sparkle.framework next to the binary (`swift run` / `just dev`).
                // build-dmg.sh adds @executable_path/../Frameworks for the .app bundle.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"])
            ]
        ),
        .testTarget(
            name: "KeylyTests",
            dependencies: ["Keyly"],
            path: "Tests/KeylyTests"
        )
    ]
)
