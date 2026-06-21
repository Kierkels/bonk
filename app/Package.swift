// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bonk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bonk",
            path: "Sources/Bonk"
        ),
        .testTarget(
            name: "BonkTests",
            dependencies: ["Bonk"],
            path: "Tests/BonkTests"
        )
    ]
)
