import Foundation

// Low-disk and full-Trash alerts (spec 011 §4). The thresholds are shared with Health
// (spec 012 §1), so the low-disk notification fires the moment Health turns orange.

/// The shared settings and their choices (build spec §6.11). Gigabytes are decimal, like Finder.
public enum AlertSettings {
    public static let gigabyte: Int64 = 1_000_000_000
    public static let lowDiskChoicesGB = [10, 20, 50]
    public static let lowDiskDefaultGB = 20
    public static let trashChoicesGB = [1, 5, 10, 20]
    public static let trashDefaultGB = 5

    // UserDefaults keys, used by the app.
    public static let lowDiskKey = "lowDiskGB"
    public static let trashKey = "trashGB"
    public static let lowDiskAlertKey = "lowDiskAlertOn"
    public static let trashAlertKey = "trashAlertOn"
}

/// One alert's fire / re-arm rule. Fires once when the value crosses the line; re-arms when the
/// value is clearly back on the good side, or after 24 hours if still on the bad side (at most
/// one reminder a day).
public struct ThresholdAlert: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Low disk: bad below the line, re-arms above line + 5 GB.
        case lowDisk
        /// Full Trash: bad above the line, re-arms below 80 % of it.
        case fullTrash
    }

    public let kind: Kind
    public private(set) var lastFired: Date?
    public static let repeatAfter: TimeInterval = 24 * 3600

    public init(kind: Kind, lastFired: Date? = nil) { self.kind = kind; self.lastFired = lastFired }

    public func isBad(_ value: Int64, line: Int64) -> Bool {
        switch kind {
        case .lowDisk: value < line
        case .fullTrash: value > line
        }
    }

    func isRearmed(_ value: Int64, line: Int64) -> Bool {
        switch kind {
        case .lowDisk: value > line + 5 * AlertSettings.gigabyte
        case .fullTrash: Double(value) < Double(line) * 0.8
        }
    }

    /// Feeds one measurement; returns true when a notification should be sent now.
    public mutating func check(_ value: Int64, line: Int64, now: Date) -> Bool {
        if let fired = lastFired {
            if isRearmed(value, line: line) { lastFired = nil; return false }
            guard isBad(value, line: line), now.timeIntervalSince(fired) >= Self.repeatAfter else { return false }
        } else if !isBad(value, line: line) {
            return false
        }
        lastFired = now
        return true
    }
}
