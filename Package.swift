// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RepFlowCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "RepFlowCore", targets: ["RepFlowCore"])],
    targets: [
        .target(name: "RepFlowCore"),
        .testTarget(name: "RepFlowCoreTests", dependencies: ["RepFlowCore"])
    ]
)
