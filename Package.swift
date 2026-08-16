// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeamsMeetingStatus",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TeamsMeetingStatus", targets: ["TeamsMeetingStatus"])],
    targets: [
        .executableTarget(name: "TeamsMeetingStatus"),
        .testTarget(name: "TeamsMeetingStatusTests", dependencies: ["TeamsMeetingStatus"])
    ]
)
