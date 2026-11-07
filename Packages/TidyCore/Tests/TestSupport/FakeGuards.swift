import RuleEngine

/// A scripted system for guard checks.
public struct FakeGuards: GuardEnvironment {
    public var running: Set<String>
    public var processes: Set<String>
    public var installed: Set<String>
    public var failing: Bool

    public init(running: Set<String> = [], processes: Set<String> = [], installed: Set<String> = [], failing: Bool = false) {
        self.running = running
        self.processes = processes
        self.installed = installed
        self.failing = failing
    }

    public func runningBundleIDs() throws -> Set<String> {
        if failing { throw GuardUnavailable(what: "running apps") }
        return running
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
