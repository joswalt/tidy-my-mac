import AppKit
import Monitors
import Observation
import RuleEngine
import RunLog
import UserNotifications

/// Disk, Trash, alerts, Health signals and reminders (specs 011 §4, 012). Shared by the menu bar
/// and Health, so the two always agree. No background scanning: storage is checked every
/// 5 minutes and on wake; the Trash when it changes.
@MainActor @Observable
final class StatusModel {
    weak var app: AppModel?
    private let defaults = UserDefaults.standard

    var storage: StorageSample?
    var trashBytes: Int64?
    var checkedAt: Date?
    var notificationsDenied = false

    // Shared settings (build spec §6.11).
    var lowDiskGB: Int { didSet { defaults.set(lowDiskGB, forKey: AlertSettings.lowDiskKey); checkAlerts() } }
    var trashGB: Int { didSet { defaults.set(trashGB, forKey: AlertSettings.trashKey); checkAlerts() } }
    var lowDiskAlertOn: Bool { didSet { defaults.set(lowDiskAlertOn, forKey: AlertSettings.lowDiskAlertKey) } }
    var trashAlertOn: Bool { didSet { defaults.set(trashAlertOn, forKey: AlertSettings.trashAlertKey) } }
    var remindersOn: Bool { didSet { defaults.set(remindersOn, forKey: ReminderSchedule.keyOn); rescheduleReminders() } }
    var reminderInterval: ReminderInterval { didSet { defaults.set(reminderInterval.rawValue, forKey: ReminderSchedule.keyInterval); rescheduleReminders() } }
    var reminderMinutes: Int { didSet { defaults.set(reminderMinutes, forKey: ReminderSchedule.keyMinutes); rescheduleReminders() } }

    private var lowDiskAlert: ThresholdAlert
    private var trashAlert: ThresholdAlert
    private var timer: Timer?
    private var trashWatcher: FolderWatcher?
    private var trashDebounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AlertSettings.lowDiskKey: AlertSettings.lowDiskDefaultGB, AlertSettings.trashKey: AlertSettings.trashDefaultGB,
            AlertSettings.lowDiskAlertKey: true, AlertSettings.trashAlertKey: true,
            ReminderSchedule.keyOn: true, ReminderSchedule.keyInterval: ReminderInterval.default.rawValue,
            ReminderSchedule.keyMinutes: ReminderSchedule.defaultMinutes, "showInMenuBar": true,
        ])
    }

    init() {
        Self.registerDefaults()
        let d = UserDefaults.standard
        lowDiskGB = d.integer(forKey: AlertSettings.lowDiskKey)
        trashGB = d.integer(forKey: AlertSettings.trashKey)
        lowDiskAlertOn = d.bool(forKey: AlertSettings.lowDiskAlertKey)
        trashAlertOn = d.bool(forKey: AlertSettings.trashAlertKey)
        remindersOn = d.bool(forKey: ReminderSchedule.keyOn)
        reminderInterval = ReminderInterval(rawValue: d.string(forKey: ReminderSchedule.keyInterval) ?? "") ?? .default
        reminderMinutes = d.integer(forKey: ReminderSchedule.keyMinutes)
        lowDiskAlert = ThresholdAlert(kind: .lowDisk, lastFired: d.object(forKey: "lowDiskLastFired") as? Date)
        trashAlert = ThresholdAlert(kind: .fullTrash, lastFired: d.object(forKey: "trashLastFired") as? Date)
        if d.object(forKey: "firstLaunch") == nil { d.set(Date(), forKey: "firstLaunch") }
    }

    /// Starts the 5-minute disk check and the wake observer (spec 011 §4).
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkStorage() } }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStorage() }
        })
        refresh()
        rescheduleReminders()
        refreshNotificationStatus()
    }

    var lowDiskLine: Int64 { Int64(lowDiskGB) * AlertSettings.gigabyte }
    var trashLine: Int64 { Int64(trashGB) * AlertSettings.gigabyte }
    var hasFullDiskAccess: Bool { app?.fullDiskAccess == .granted }

    // MARK: Measuring

    /// Launch, Health opening, and after every run (spec 012 §1).
    func refresh() {
        checkStorage()
        measureTrash()
    }

    func checkStorage() {
        storage = StorageSample.read(volume: URL(fileURLWithPath: "/"))
        checkedAt = Date()
        checkAlerts()
    }

    func measureTrash() {
        guard hasFullDiskAccess, let home = app?.context?.home else { trashBytes = nil; return }
        Task {
            let size = await Task.detached { TrashSize.measure(home: home) }.value
            trashBytes = size
            checkAlerts()
        }
    }

    /// Watches `~/.Trash` while Full Disk Access is on, with a 30 s debounce (spec 011 §4).
    func fullDiskAccessChanged() {
        guard hasFullDiskAccess, let home = app?.context?.home else { trashWatcher = nil; trashBytes = nil; return }
        if trashWatcher == nil {
            trashWatcher = FolderWatcher(path: home.trash.path) { [weak self] in
                Task { @MainActor in self?.trashChanged() }
            }
        }
        measureTrash()
    }

    private func trashChanged() {
        trashDebounce?.cancel()
        trashDebounce = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { measureTrash() }
        }
    }

    // MARK: Alerts

    var lowDiskActive: Bool { storage.map { lowDiskAlert.isBad($0.availableBytes, line: lowDiskLine) } ?? false }
    var trashActive: Bool { hasFullDiskAccess && (trashBytes.map { trashAlert.isBad($0, line: trashLine) } ?? false) }

    /// The menu bar dot: an alert condition whose switch is on.
    var showsBadge: Bool { (lowDiskAlertOn && lowDiskActive) || (trashAlertOn && trashActive) }

    private func checkAlerts() {
        let now = Date()
        if let s = storage, lowDiskAlert.check(s.availableBytes, line: lowDiskLine, now: now), lowDiskAlertOn {
            Notifier.post(id: "lowDisk", category: Notifier.lowDisk, body: "Your startup disk has \(MonitorFormat.bytes(s.availableBytes)) free.")
        }
        if hasFullDiskAccess, let t = trashBytes, trashAlert.check(t, line: trashLine, now: now), trashAlertOn {
            Notifier.post(id: "fullTrash", category: Notifier.fullTrash, body: "Your Trash holds \(MonitorFormat.bytes(t)).")
        }
        defaults.set(lowDiskAlert.lastFired, forKey: "lowDiskLastFired")
        defaults.set(trashAlert.lastFired, forKey: "trashLastFired")
    }

    // MARK: Health (spec 012 §1)

    var junkLeft: (bytes: Int64, scanned: Date)? {
        guard let date = defaults.object(forKey: "junkScanDate") as? Date else { return nil }
        return (Int64(defaults.integer(forKey: "junkLeftBytes")), date)
    }

    /// After a Smart Care scan: what it found, not counting the Trash bins (they have their own line).
    func recordJunk(found: Int64) {
        defaults.set(Int(found), forKey: "junkLeftBytes")
        defaults.set(Date(), forKey: "junkScanDate")
    }

    /// After a real Smart Care run: what is left of what the scan found.
    func recordCleaned(_ bytes: Int64) {
        guard let j = junkLeft else { return }
        defaults.set(Int(max(0, j.bytes - bytes)), forKey: "junkLeftBytes")
    }

    var signals: [HealthSignal] {
        Health.signals(HealthInputs(now: Date(), availableBytes: storage?.availableBytes, lowDiskGB: lowDiskGB,
                                    lastSmartCare: app?.lastSmartCare?.header.start, reminderInterval: reminderInterval,
                                    junkLeft: junkLeft, trashBytes: trashBytes, trashGB: trashGB,
                                    hasFullDiskAccess: hasFullDiskAccess, helperReady: app?.helper.state.isReady ?? false))
    }

    var overall: HealthLevel { Health.overall(signals) }

    // MARK: Reminders (spec 012 §2)

    var firstLaunch: Date { defaults.object(forKey: "firstLaunch") as? Date ?? Date() }

    /// Local calendar notifications, so the app need not be running. Rescheduled on launch, every
    /// Smart Care completion and every settings change.
    func rescheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["reminder.0", "reminder.1"])
        guard remindersOn else { center.removePendingNotificationRequests(withIdentifiers: ["reminder.snooze"]); return }
        let last = app?.lastSmartCare?.header.start
        let plan = ReminderSchedule.plan(lastRun: last, firstLaunch: firstLaunch, interval: reminderInterval,
                                         minutesOfDay: reminderMinutes, now: Date())
        for (i, date) in plan.pending.enumerated() {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            Notifier.post(id: "reminder.\(i)", category: Notifier.reminder, body: ReminderSchedule.message(lastRun: last, at: date),
                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
    }

    /// The reminder's second action: one day later.
    func snoozeReminder() {
        Notifier.post(id: "reminder.snooze", category: Notifier.reminder,
                      body: ReminderSchedule.message(lastRun: app?.lastSmartCare?.header.start, at: Date().addingTimeInterval(86400)),
                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 86400, repeats: false))
    }

    func smartCareCompleted(cleanedBytes: Int64) {
        recordCleaned(cleanedBytes)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder.snooze"])
        rescheduleReminders()
    }

    func refreshNotificationStatus() {
        Task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = s.authorizationStatus == .denied
        }
    }

    /// macOS's prompt, asked after setup (alerts) or on the first Smart Care Done screen (reminders).
    func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            refreshNotificationStatus()
            rescheduleReminders()
        }
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Posting and answering notifications (specs 011 §4, 012 §2). Buttons only open the app;
/// nothing a notification does removes a file.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let lowDisk = "lowDisk", fullTrash = "fullTrash", reminder = "reminder"
    static let shared = Notifier()
    /// Set by the app model; called on the main actor with the category and action.
    @MainActor var onResponse: ((String, String) -> Void)?

    @MainActor
    static func install() {
        let c = UNUserNotificationCenter.current()
        c.delegate = shared
        c.setNotificationCategories([
            UNNotificationCategory(identifier: lowDisk, actions: [UNNotificationAction(identifier: "openSpaceLens", title: "Open Space Lens", options: [.foreground])],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: fullTrash, actions: [UNNotificationAction(identifier: "reviewTrash", title: "Review Trash", options: [.foreground])],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: reminder, actions: [UNNotificationAction(identifier: "tomorrow", title: "Tomorrow", options: [])],
                                   intentIdentifiers: []),
        ])
    }

    static func post(id: String, category: String, body: String, trigger: UNNotificationTrigger? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "TidyMyMac"
        content.body = body
        content.categoryIdentifier = category
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        await MainActor.run { onResponse?(category, action) }
    }
}
