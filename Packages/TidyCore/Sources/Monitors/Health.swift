import Foundation

// Health status from six signals (spec 012 §1). No numeric score; the overall status is the
// worst signal. Pure: the app gathers the inputs, this decides the colours.

public enum HealthLevel: Int, Comparable, Sendable {
    case good = 0, worthALook = 1, needsAttention = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self { case .good: "Looks good"; case .worthALook: "Worth a look"; case .needsAttention: "Needs attention" }
    }
}

public struct HealthSignal: Identifiable, Equatable, Sendable {
    public enum ID: String, Sendable, CaseIterable {
        case freeSpace, lastSmartCare, junkFound, trash, fullDiskAccess, helper
    }
    public enum Fix: Equatable, Sendable {
        case spaceLens, runSmartCare, smartCare, emptyTrash, openSetup
    }

    public let id: ID
    public let title: String
    public let level: HealthLevel
    public let reason: String
    public let fix: Fix?

    public init(id: ID, title: String, level: HealthLevel, reason: String, fix: Fix?) {
        self.id = id; self.title = title; self.level = level; self.reason = reason; self.fix = fix
    }
}

public struct HealthInputs: Sendable {
    public var now: Date
    /// Real free space (not counting purgeable); nil if unreadable.
    public var freeBytes: Int64?
    public var lowDiskGB: Int
    public var lastSmartCare: Date?
    public var reminderInterval: ReminderInterval
    /// What the last Smart Care scan found and was not cleaned, and when.
    public var junkLeft: (bytes: Int64, scanned: Date)?
    /// Nil without Full Disk Access: the row is hidden then.
    public var trashBytes: Int64?
    public var trashGB: Int
    public var hasFullDiskAccess: Bool
    public var helperReady: Bool

    public init(now: Date, freeBytes: Int64?, lowDiskGB: Int, lastSmartCare: Date?, reminderInterval: ReminderInterval,
                junkLeft: (bytes: Int64, scanned: Date)?, trashBytes: Int64?, trashGB: Int, hasFullDiskAccess: Bool, helperReady: Bool) {
        self.now = now; self.freeBytes = freeBytes; self.lowDiskGB = lowDiskGB; self.lastSmartCare = lastSmartCare
        self.reminderInterval = reminderInterval; self.junkLeft = junkLeft; self.trashBytes = trashBytes; self.trashGB = trashGB
        self.hasFullDiskAccess = hasFullDiskAccess; self.helperReady = helperReady
    }
}

public enum Health {
    /// Red below this, fixed (Health only, no notification).
    public static let redLine: Int64 = 10 * AlertSettings.gigabyte
    /// "Junk found last time" turns orange above this.
    public static let junkLine: Int64 = 5 * AlertSettings.gigabyte

    public static func overall(_ signals: [HealthSignal]) -> HealthLevel { signals.map(\.level).max() ?? .good }

    public static func signals(_ i: HealthInputs, calendar: Calendar = .current) -> [HealthSignal] {
        var out: [HealthSignal] = []
        let fmt = MonitorFormat.bytes

        // Free disk space.
        if let free = i.freeBytes {
            let orange = Int64(i.lowDiskGB) * AlertSettings.gigabyte
            let level: HealthLevel = free < redLine ? .needsAttention : (free < orange ? .worthALook : .good)
            let reason = switch level {
            case .good: "\(fmt(free)) free"
            case .worthALook: "\(fmt(free)) free, below your \(i.lowDiskGB) GB line"
            case .needsAttention: "Only \(fmt(free)) free. macOS needs room to update and run smoothly."
            }
            out.append(HealthSignal(id: .freeSpace, title: "Free disk space", level: level, reason: reason, fix: level == .good ? nil : .spaceLens))
        } else {
            out.append(HealthSignal(id: .freeSpace, title: "Free disk space", level: .good, reason: "Couldn't read the startup disk", fix: nil))
        }

        // Last Smart Care: orange if never, or more than 2× the reminder interval ago.
        if let last = i.lastSmartCare {
            let limit = calendar.date(byAdding: i.reminderInterval.component, value: 2 * i.reminderInterval.amount, to: last) ?? last
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: i.now)).day ?? 0)
            let ago = days == 0 ? "today" : (days == 1 ? "yesterday" : "\(days) days ago")
            let late = i.now > limit
            out.append(HealthSignal(id: .lastSmartCare, title: "Last Smart Care", level: late ? .worthALook : .good,
                                    reason: "Last run \(ago)", fix: late ? .runSmartCare : nil))
        } else {
            out.append(HealthSignal(id: .lastSmartCare, title: "Last Smart Care", level: .worthALook,
                                    reason: "Not run yet", fix: .runSmartCare))
        }

        // Junk found last time and left.
        if let junk = i.junkLeft {
            let date = junk.scanned.formatted(date: .abbreviated, time: .omitted)
            let level: HealthLevel = junk.bytes > junkLine ? .worthALook : .good
            out.append(HealthSignal(id: .junkFound, title: "Junk found last time", level: level,
                                    reason: "\(fmt(junk.bytes)) left after the scan on \(date)", fix: level == .good ? nil : .smartCare))
        } else {
            out.append(HealthSignal(id: .junkFound, title: "Junk found last time", level: .good, reason: "No scan yet", fix: nil))
        }

        // Trash size (hidden without Full Disk Access).
        if i.hasFullDiskAccess, let trash = i.trashBytes {
            let level: HealthLevel = trash > Int64(i.trashGB) * AlertSettings.gigabyte ? .worthALook : .good
            out.append(HealthSignal(id: .trash, title: "Trash", level: level,
                                    reason: level == .good ? "\(fmt(trash)) in the Trash" : "\(fmt(trash)) in the Trash, over your \(i.trashGB) GB line",
                                    fix: level == .good ? nil : .emptyTrash))
        }

        out.append(HealthSignal(id: .fullDiskAccess, title: "Full Disk Access", level: i.hasFullDiskAccess ? .good : .worthALook,
                                reason: i.hasFullDiskAccess ? "On" : "Off: the Trash, app containers and iOS backups can't be checked",
                                fix: i.hasFullDiskAccess ? nil : .openSetup))
        out.append(HealthSignal(id: .helper, title: "Admin helper", level: i.helperReady ? .good : .worthALook,
                                reason: i.helperReady ? "Ready" : "Not approved: system caches and maintenance are off",
                                fix: i.helperReady ? nil : .openSetup))
        return out
    }
}

// MARK: - Reminders (spec 012 §2)

public enum ReminderInterval: String, CaseIterable, Sendable, Codable {
    case week, twoWeeks, month

    public static let `default` = ReminderInterval.twoWeeks

    public var title: String {
        switch self { case .week: "Every week"; case .twoWeeks: "Every 2 weeks"; case .month: "Every month" }
    }
    public var component: Calendar.Component { self == .month ? .month : .day }
    public var amount: Int {
        switch self { case .week: 7; case .twoWeeks: 14; case .month: 1 }
    }
}

public struct ReminderPlan: Equatable, Sendable {
    public var due: Date
    public var repeatDate: Date
    /// The dates still to schedule (those after `now`).
    public var pending: [Date]
}

public enum ReminderSchedule {
    public static let keyOn = "remindersOn"
    public static let keyInterval = "reminderInterval"
    public static let keyMinutes = "reminderMinutes"
    public static let defaultMinutes = 10 * 60
    public static let repeatAfterDays = 3

    /// Due = (last completed Smart Care, or first launch if never) + interval, at the time of day.
    /// One repeat 3 days later; then silent until the next Smart Care run. Past dates are dropped:
    /// a Mac asleep at the time gets the notification on wake from the system.
    public static func plan(lastRun: Date?, firstLaunch: Date, interval: ReminderInterval, minutesOfDay: Int,
                            now: Date, calendar: Calendar = .current) -> ReminderPlan {
        let base = lastRun ?? firstLaunch
        let day = calendar.date(byAdding: interval.component, value: interval.amount, to: base) ?? base
        let due = calendar.date(bySettingHour: minutesOfDay / 60, minute: minutesOfDay % 60, second: 0, of: day) ?? day
        let rep = calendar.date(byAdding: .day, value: repeatAfterDays, to: due) ?? due
        return ReminderPlan(due: due, repeatDate: rep, pending: [due, rep].filter { $0 > now })
    }

    /// "Time for Smart Care. Last run 16 days ago."
    public static func message(lastRun: Date?, at date: Date, calendar: Calendar = .current) -> String {
        guard let lastRun else { return "Time for Smart Care. You haven't run it yet." }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastRun), to: calendar.startOfDay(for: date)).day ?? 0
        return "Time for Smart Care. Last run \(days == 1 ? "1 day" : "\(days) days") ago."
    }
}
