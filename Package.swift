// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Melies",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Melies",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Melies"
        ),
        .testTarget(
            name: "MeliesTests",
            dependencies: ["Melies"],
            path: "Tests/MeliesTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
