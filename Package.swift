// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MSTeamsStatusSender",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MSTeamsStatusSender", targets: ["MSTeamsStatusSender"])],
    targets: [
        .executableTarget(name: "MSTeamsStatusSender"),
        .testTarget(name: "MSTeamsStatusSenderTests", dependencies: ["MSTeamsStatusSender"])
    ]
)
