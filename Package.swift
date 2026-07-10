// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentKit", targets: ["AgentKit"]),
        .executable(name: "agentbar", targets: ["agentbar-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0"),
    ],
    targets: [
        .target(name: "AgentKit"),
        .executableTarget(
            name: "agentbar-cli",
            dependencies: [
                "AgentKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit"]),
    ]
)
