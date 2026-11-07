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
        .target(name: "HelperProtocol", dependencies: ["SafetyFloor"]),
        .target(name: "HelperCore", dependencies: ["SafetyFloor", "HelperProtocol"]),
        .target(name: "RuleEngine", dependencies: ["SafetyFloor", "RunLog"]),
        .target(name: "AppInventory", dependencies: ["SafetyFloor", "RuleEngine", "RunLog"]),
        .target(name: "DiskAnalysis", dependencies: ["SafetyFloor"]),
        .target(name: "SystemTasks", dependencies: ["SafetyFloor", "HelperProtocol"]),
        .target(name: "Monitors", dependencies: ["SafetyFloor"]),
        .target(name: "RunLog"),

        // Command-line rule lint, run by scripts/lint-rules.sh.
        .executableTarget(name: "tidy-rule-lint", dependencies: ["RuleEngine", "SafetyFloor"]),

        // Test-only support: TestHome fixtures and snapshots (spec 017 §2). Never linked by the app.
        .target(name: "TestSupport", dependencies: ["SafetyFloor", "RuleEngine", "HelperCore", "HelperProtocol"], path: "Tests/TestSupport"),

        .testTarget(name: "SafetyFloorTests", dependencies: ["SafetyFloor", "TestSupport"]),
        .testTarget(name: "HelperProtocolTests", dependencies: ["HelperProtocol", "HelperCore", "SafetyFloor", "TestSupport"]),
        .testTarget(name: "HelperCoreTests", dependencies: ["HelperCore", "HelperProtocol", "SafetyFloor", "TestSupport"]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine", "RunLog", "TestSupport"], exclude: ["Fixtures"]),
        .testTarget(name: "AppInventoryTests", dependencies: ["AppInventory", "RuleEngine", "RunLog", "SafetyFloor", "TestSupport"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "DiskAnalysisTests", dependencies: ["DiskAnalysis", "RuleEngine", "RunLog", "SafetyFloor", "TestSupport"]),
        .testTarget(name: "SystemTasksTests", dependencies: ["SystemTasks", "SafetyFloor", "TestSupport"]),
        .testTarget(name: "MonitorsTests", dependencies: ["Monitors", "SafetyFloor", "TestSupport"]),
        .testTarget(name: "RunLogTests", dependencies: ["RunLog", "TestSupport"]),
        // The core property (spec 017 §4.1): a run removes exactly what was selected, nothing else.
        .testTarget(name: "EndToEndTests", dependencies: [
            "RuleEngine", "AppInventory", "DiskAnalysis", "RunLog", "SafetyFloor", "TestSupport",
        ]),
    ]
)
