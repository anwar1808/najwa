// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Najwa",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Najwa",
            path: "Sources/Najwa",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
