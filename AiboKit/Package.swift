// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AiboKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "AiboCore", targets: ["AiboCore"]),
        .library(name: "AiboIngest", targets: ["AiboIngest"]),
        .library(name: "AiboLLM", targets: ["AiboLLM"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AiboCore"
        ),
        .target(
            name: "AiboIngest",
            dependencies: ["AiboCore"]
        ),
        .target(
            name: "AiboLLM",
            dependencies: ["AiboCore"]
        ),
        .testTarget(
            name: "AiboCoreTests",
            dependencies: ["AiboCore"]
        ),
        .testTarget(
            name: "AiboIngestTests",
            dependencies: ["AiboIngest"]
        ),
    ]
)
