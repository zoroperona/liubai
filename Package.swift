// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlanIsland",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PlanIsland", targets: ["PlanIsland"])],
    targets: [
        .target(name: "PlanCore"),
        .executableTarget(name: "PlanIsland", dependencies: ["PlanCore"]),
        .testTarget(name: "PlanCoreTests", dependencies: ["PlanCore"])
    ]
)
