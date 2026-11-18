// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WooshKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WooshKit", targets: ["WooshKit"]),
        .library(name: "WooshKitTesting", targets: ["WooshKitTesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.29.0")
    ],
    targets: [
        .target(name: "WooshKit", dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]),
        .target(name: "WooshKitTesting", dependencies: ["WooshKit"]),
        .testTarget(name: "WooshKitTests", dependencies: ["WooshKit", "WooshKitTesting"])
    ]
)
