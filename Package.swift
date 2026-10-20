// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Melies",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Melies",
            dependencies: [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            path: "Sources/Melies"
        ),
    ],
    swiftLanguageModes: [.v5]
)
