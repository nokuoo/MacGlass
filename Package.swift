// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MacGlass",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacGlass", targets: ["MacGlass"])
    ],
    targets: [
        .target(
            name: "MacGlassCore",
            path: "Sources/MacGlassCore"
        ),
        .executableTarget(
            name: "MacGlass",
            dependencies: ["MacGlassCore"],
            path: "Sources/MacGlass"
        ),
        .testTarget(
            name: "MacGlassCoreTests",
            dependencies: ["MacGlassCore"],
            path: "Tests/MacGlassCoreTests"
        )
    ]
)
