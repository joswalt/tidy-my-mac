import AppKit
import Monitors
import Observation

/// Live CPU, memory, storage and network figures for the popover (spec 011 §2–3). Samples only
/// while the popover is open; pauses on sleep and screen lock. Nothing is kept while closed.
@MainActor @Observable
final class MenuBarMonitor {
    static let historyLength = 60

    var cpuHistory: [Double] = []
    var memory: MemorySample?
    var down: Double = 0
    var up: Double = 0

    private var lastCPU: CPUTicks?
    private var lastNet: (counters: NetworkCounters, time: Date)?
    private var timers: [Timer] = []
    private var isOpen = false
    private var paused = false
    private var pressureFallback: MemoryPressureWatcher?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    weak var status: StatusModel?

    var cpu: Double? { cpuHistory.last }

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        for (center, name, pause) in [(ws, NSWorkspace.willSleepNotification, true), (ws, NSWorkspace.didWakeNotification, false),
                                      (dist as NotificationCenter, Notification.Name("com.apple.screenIsLocked"), true),
                                      (dist as NotificationCenter, Notification.Name("com.apple.screenIsUnlocked"), false)] {
            let o = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPaused(pause) }
            }
            observers.append((center, o))
        }
    }

    func open() {
        isOpen = true
        // The sparkline and network rate start fresh each time (spec 011 §3).
        cpuHistory = []
        lastCPU = nil
        lastNet = nil
        down = 0
        up = 0
        status?.checkStorage()
        startTimers()
    }

    func close() {
        isOpen = false
        stopTimers()
    }

    private func setPaused(_ p: Bool) {
        paused = p
        if p { stopTimers() } else if isOpen { startTimers() }
    }

    private func startTimers() {
        guard timers.isEmpty, isOpen, !paused else { return }
        sampleFast()
        sampleMemory()
        add(1) { $0.sampleFast() }
        add(2) { $0.sampleMemory() }
        add(30) { $0.status?.checkStorage() }
    }

    private func add(_ interval: TimeInterval, _ body: @escaping @MainActor (MenuBarMonitor) -> Void) {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self { body(self) } }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers = []
    }

    private func sampleFast() {
        if let now = CPUTicks.read() {
            if let last = lastCPU, let u = CPUTicks.usage(from: last, to: now) {
                cpuHistory.append(u)
                if cpuHistory.count > Self.historyLength { cpuHistory.removeFirst(cpuHistory.count - Self.historyLength) }
            }
            lastCPU = now
        }
        if let c = NetworkCounters.read() {
            let t = Date()
            if let last = lastNet {
                (down, up) = NetworkCounters.rate(from: last.counters, to: c, seconds: t.timeIntervalSince(last.time))
            }
            lastNet = (c, t)
        }
    }

    private func sampleMemory() {
        guard var m = MemorySample.read() else { return }
        if m.pressure == nil {
            // sysctl not readable: fall back to memory-pressure events (spec 011 §7).
            if pressureFallback == nil { pressureFallback = MemoryPressureWatcher() }
            m.pressure = pressureFallback?.current
        }
        memory = m
    }
}
