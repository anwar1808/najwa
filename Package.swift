// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Najwa",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Local shallow checkouts (sibling dirs) used as overrides to avoid
        // SwiftPM full-cloning large repos over a flaky connection. See README.
        // - whisperkit v0.13.1 (lean: swift-transformers only, no Vapor)
        // - swift-collections 1.6.0 (transitive dep of Jinja; full clone kept
        //   failing mid-transfer, so it's vendored locally)
        .package(path: "/Users/annie/Annie-Claude/whisperkit"),
        .package(path: "/Users/annie/Annie-Claude/swift-collections")
    ],
    targets: [
        .executableTarget(
            name: "Najwa",
            dependencies: [
                .product(name: "WhisperKit", package: "whisperkit")
            ],
            path: "Sources/Najwa",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
