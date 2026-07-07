// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Strays",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Strays", targets: ["Strays"])
    ],
    targets: [
        .executableTarget(
            name: "Strays",
            path: "Sources/Strays",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
