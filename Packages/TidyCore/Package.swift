// swift-tools-version: 6.0
// TidyCore: every library the app and helper share (spec 016 §3).
// Libraries never import SwiftUI and never reach the real home folder directly (spec 017 §2).
import PackageDescription

let package = Package(
    name: "TidyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SafetyFloor", targets: ["SafetyFloor"]),
        .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
        .library(name: "HelperCore", targets: ["HelperCore"]),
        .library(name: "RuleEngine", targets: ["RuleEngine"]),
        .library(name: "AppInventory", targets: ["AppInventory"]),
        .library(name: "DiskAnalysis", targets: ["DiskAnalysis"]),
        .library(name: "SystemTasks", targets: ["SystemTasks"]),
        .library(name: "Monitors", targets: ["Monitors"]),
        .library(name: "RunLog", targets: ["RunLog"]),
    ],
    targets: [
        .target(name: "SafetyFloor"),
        .target(name: "HelperProtocol"),
        .target(name: "HelperCore", dependencies: ["SafetyFloor", "HelperProtocol"]),
        .target(name: "RuleEngine", dependencies: ["SafetyFloor"]),
        .target(name: "AppInventory", dependencies: ["SafetyFloor", "RuleEngine"]),
        .target(name: "DiskAnalysis", dependencies: ["SafetyFloor"]),
        .target(name: "SystemTasks", dependencies: ["HelperProtocol"]),
        .target(name: "Monitors"),
        .target(name: "RunLog"),

        .testTarget(name: "SafetyFloorTests", dependencies: ["SafetyFloor"]),
        .testTarget(name: "HelperProtocolTests", dependencies: ["HelperProtocol"]),
        .testTarget(name: "HelperCoreTests", dependencies: ["HelperCore"]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine"]),
        .testTarget(name: "AppInventoryTests", dependencies: ["AppInventory"]),
        .testTarget(name: "DiskAnalysisTests", dependencies: ["DiskAnalysis"]),
        .testTarget(name: "SystemTasksTests", dependencies: ["SystemTasks"]),
        .testTarget(name: "MonitorsTests", dependencies: ["Monitors"]),
        .testTarget(name: "RunLogTests", dependencies: ["RunLog"]),
    ]
)
