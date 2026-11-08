import RuleEngine

/// A scripted system for guard checks.
public struct FakeGuards: GuardEnvironment {
    public var running: Set<String>
    /// Open apps with names (for owner matching); their bundle IDs count as running too.
    public var apps: [RunningApp]
    public var processes: Set<String>
    public var installed: Set<String>
    public var failing: Bool

    public init(running: Set<String> = [], apps: [RunningApp] = [], processes: Set<String> = [], installed: Set<String> = [], failing: Bool = false) {
        self.running = running
        self.apps = apps
        self.processes = processes
        self.installed = installed
        self.failing = failing
    }

    public func runningBundleIDs() throws -> Set<String> {
        if failing { throw GuardUnavailable(what: "running apps") }
        return running.union(apps.map(\.bundleID))
    }

    public func runningApps() throws -> [RunningApp] {
        if failing { throw GuardUnavailable(what: "running apps") }
        return apps + running.sorted().map { RunningApp(bundleID: $0, name: $0) }
    }

    public func runningProcessNames() throws -> Set<String> {
        if failing { throw GuardUnavailable(what: "running processes") }
        return processes
    }

    public func isAppInstalled(bundleID: String) throws -> Bool {
        if failing { throw GuardUnavailable(what: "installed apps") }
        return installed.contains(bundleID)
    }
}

/// The repo folders, found from this file's location.
public enum RepoPaths {
    public static let tidyCore: String = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // Tests/TestSupport/FakeGuards.swift
        return url.path
    }()
    public static let repoRoot: String = (tidyCore as NSString).deletingLastPathComponent.replacingOccurrences(of: "/Packages", with: "")
    public static let rules: URL = URL(fileURLWithPath: repoRoot).appendingPathComponent("Rules", isDirectory: true)
}

import Foundation
