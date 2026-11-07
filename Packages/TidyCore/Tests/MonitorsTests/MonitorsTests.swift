import Foundation
import SafetyFloor
import Testing
import TestSupport
@testable import Monitors

let GB = AlertSettings.gigabyte

struct SamplerMathTests {
    @Test func cpu() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 160, system: 70, idle: 900, nice: 70)
        #expect(CPUTicks.usage(from: a, to: b) == 100.0 / 200.0)
        #expect(CPUTicks.usage(from: a, to: a) == nil)
        #expect(CPUTicks.usage(from: b, to: a) == nil)
    }

    @Test func memory() {
        #expect(MemorySample.usedBytes(internalPages: 1000, purgeable: 200, wired: 300, compressor: 100, pageSize: 16384) == 1200 * 16384)
        #expect(MemorySample.usedBytes(internalPages: 10, purgeable: 20, wired: 0, compressor: 0, pageSize: 4096) == 0)
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
        #expect(MemoryPressure(sysctlLevel: 3) == nil)
    }

    @Test func networkInterfacesAndRates() {
        #expect(NetworkCounters.counts(interface: "en0", isUp: true, isLoopback: false))
        #expect(!NetworkCounters.counts(interface: "en1", isUp: false, isLoopback: false))
        for n in ["utun3", "awdl0", "llw0", "bridge0", "ap1", "lo0"] {
            #expect(!NetworkCounters.counts(interface: n, isUp: true, isLoopback: n == "lo0"))
        }
        let a = NetworkCounters(inBytes: 5_000_000_000, outBytes: 100)
        let b = NetworkCounters(inBytes: 5_002_000_000, outBytes: 50)  // out counter reset
        let r = NetworkCounters.rate(from: a, to: b, seconds: 2)
        #expect(r.down == 1_000_000 && r.up == 0)
        #expect(MonitorFormat.rate(1_234_567) == "1.2 MB/s")
        #expect(MonitorFormat.rate(84_000) == "84 KB/s")
    }

    @Test func storage() {
        let s = StorageSample(freeBytes: 80 * GB, finderAvailableBytes: 84 * GB, totalBytes: 494 * GB)
        #expect(s.purgeableBytes == 4 * GB)
        #expect(s.usedFraction == Double(414) / 494)  // used counts purgeable space as used
        // The live reading: free never exceeds Finder's figure.
        if let live = StorageSample.read(volume: URL(fileURLWithPath: "/")) { #expect(live.freeBytes <= live.finderAvailableBytes) }
        #expect(StorageSample.read(volume: URL(fileURLWithPath: "/")) != nil)  // read-only system call
    }

    /// The real readers are read-only system calls; they must answer on this Mac.
    @Test func liveReadersAnswer() throws {
        let cpu = try #require(CPUTicks.read())
        #expect(cpu.total > 0)
        let mem = try #require(MemorySample.read())
        #expect(mem.totalBytes > 0 && mem.usedBytes > 0 && mem.usedBytes <= mem.totalBytes)
        let net = try #require(NetworkCounters.read())
        print("live: mem \(mem.usedBytes)/\(mem.totalBytes) pressure \(String(describing: mem.pressure)) net \(net.inBytes)/\(net.outBytes)")
    }

    @Test func trashSizeCountsAllocatedBytes() throws {
        let t = try TestHome("trashsize")
        defer { t.cleanUp() }
        #expect(TrashSize.measure(home: t.home) == nil)  // no Trash folder at all
        try t.file(".Trash/a.bin", size: 10_000)
        try t.file(".Trash/folder/b.bin", size: 5_000)
        let size = try #require(TrashSize.measure(home: t.home))
        #expect(size >= 15_000)
    }
}

/// The macro can't call a mutating method, so tests hold the alert in a box.
final class AlertBox {
    var alert: ThresholdAlert
    init(_ kind: ThresholdAlert.Kind) { alert = ThresholdAlert(kind: kind) }
    func check(_ v: Int64, line: Int64, now: Date) -> Bool { alert.check(v, line: line, now: now) }
}

struct AlertTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func lowDiskFiresOnceAndReArms() {
        let a = AlertBox(.lowDisk)
        let line = 20 * GB
        #expect(!a.check(25 * GB, line: line, now: t0))
        #expect(a.check(19 * GB, line: line, now: t0))            // drops below: fire
        #expect(!a.check(14 * GB, line: line, now: t0 + 3600))    // still low: quiet
        #expect(!a.check(22 * GB, line: line, now: t0 + 7200))    // above line but not +5 GB: not re-armed
        #expect(!a.check(19 * GB, line: line, now: t0 + 7300))
        #expect(a.check(19 * GB, line: line, now: t0 + 24 * 3600))  // a day later, still low: one reminder
        #expect(!a.check(26 * GB, line: line, now: t0 + 25 * 3600)) // above line + 5 GB: re-armed
        #expect(a.check(18 * GB, line: line, now: t0 + 26 * 3600))  // so it fires again at once
    }

    @Test func fullTrashReArmsBelowEightyPercent() {
        let a = AlertBox(.fullTrash)
        let line = 5 * GB
        #expect(!a.check(5 * GB, line: line, now: t0))            // at the line is not over it
        #expect(a.check(7_300_000_000, line: line, now: t0))
        #expect(!a.check(4_500_000_000, line: line, now: t0 + 60)) // below the line, above 80 %: not re-armed
        #expect(!a.check(6 * GB, line: line, now: t0 + 120))
        #expect(!a.check(3 * GB, line: line, now: t0 + 180))      // below 80 %: re-armed
        #expect(a.check(6 * GB, line: line, now: t0 + 240))
    }

    @Test func choicesAndDefaults() {
        #expect(AlertSettings.lowDiskChoicesGB == [10, 20, 50] && AlertSettings.lowDiskDefaultGB == 20)
        #expect(AlertSettings.trashChoicesGB == [1, 5, 10, 20] && AlertSettings.trashDefaultGB == 5)
    }
}

struct HealthTests {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func inputs(free: Int64? = 100 * GB, lowDisk: Int = 20, last: Date?? = nil, junk: Int64? = nil, trash: Int64? = 1 * GB,
                fda: Bool = true, helper: Bool = true) -> HealthInputs {
        HealthInputs(now: now, freeBytes: free, lowDiskGB: lowDisk,
                     lastTidyUp: last ?? now.addingTimeInterval(-3 * 86400), reminderInterval: .twoWeeks,
                     junkLeft: junk.map { ($0, now.addingTimeInterval(-86400)) }, trashBytes: trash, trashGB: 5,
                     hasFullDiskAccess: fda, helperReady: helper)
    }

    func level(_ id: HealthSignal.ID, _ i: HealthInputs) -> HealthLevel? {
        Health.signals(i, calendar: cal).first { $0.id == id }?.level
    }

    @Test func allGood() {
        let s = Health.signals(inputs(), calendar: cal)
        #expect(Health.overall(s) == .good)
        #expect(s.map(\.id) == [.freeSpace, .lastTidyUp, .junkFound, .trash, .fullDiskAccess, .helper])
    }

    @Test func freeSpaceLines() {
        #expect(level(.freeSpace, inputs(free: 21 * GB)) == .good)
        #expect(level(.freeSpace, inputs(free: 19 * GB)) == .worthALook)
        #expect(level(.freeSpace, inputs(free: 9 * GB)) == .needsAttention)
        // Setting at 10: orange and red coincide, so it goes straight to red.
        #expect(level(.freeSpace, inputs(free: 9 * GB, lowDisk: 10)) == .needsAttention)
        #expect(level(.freeSpace, inputs(free: 11 * GB, lowDisk: 10)) == .good)
        #expect(level(.freeSpace, inputs(free: 30 * GB, lowDisk: 50)) == .worthALook)
        // Overall is the worst signal.
        #expect(Health.overall(Health.signals(inputs(free: 9 * GB, fda: false), calendar: cal)) == .needsAttention)
        // The fix is Disk Map.
        #expect(Health.signals(inputs(free: 9 * GB), calendar: cal).first?.fix == .diskMap)
    }

    @Test func lastTidyUp() {
        #expect(level(.lastTidyUp, inputs(last: .some(nil))) == .worthALook)
        #expect(level(.lastTidyUp, inputs(last: now.addingTimeInterval(-27 * 86400))) == .good)
        #expect(level(.lastTidyUp, inputs(last: now.addingTimeInterval(-29 * 86400))) == .worthALook)
    }

    @Test func junkTrashAndSetup() {
        #expect(level(.junkFound, inputs(junk: 4 * GB)) == .good)
        #expect(level(.junkFound, inputs(junk: 6 * GB)) == .worthALook)
        #expect(level(.trash, inputs(trash: 6 * GB)) == .worthALook)
        #expect(level(.trash, inputs(trash: 6 * GB, fda: false)) == nil)  // hidden without FDA
        #expect(level(.fullDiskAccess, inputs(fda: false)) == .worthALook)
        #expect(level(.helper, inputs(helper: false)) == .worthALook)
        // Nothing but free space can turn red.
        let worst = Health.signals(inputs(last: .some(nil), junk: 50 * GB, trash: 50 * GB, fda: true, helper: false), calendar: cal)
        #expect(Health.overall(worst) == .worthALook)
    }
}

struct ReminderTests {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    @Test func dueFromLastRunAtTimeOfDay() {
        let p = ReminderSchedule.plan(lastRun: date("2026-11-01T18:30:00Z"), firstLaunch: date("2026-10-01T09:00:00Z"),
                                      interval: .twoWeeks, minutesOfDay: 600, now: date("2026-11-07T12:00:00Z"), calendar: cal)
        #expect(p.due == date("2026-11-15T10:00:00Z"))
        #expect(p.repeatDate == date("2026-11-18T10:00:00Z"))
        #expect(p.pending == [p.due, p.repeatDate])
    }

    @Test func neverRunCountsFromFirstLaunch() {
        let p = ReminderSchedule.plan(lastRun: nil, firstLaunch: date("2026-11-07T08:00:00Z"), interval: .week, minutesOfDay: 9 * 60 + 15,
                                      now: date("2026-11-07T08:00:00Z"), calendar: cal)
        #expect(p.due == date("2026-11-14T09:15:00Z"))
    }

    @Test func monthAndPastDates() {
        let p = ReminderSchedule.plan(lastRun: date("2026-01-31T10:00:00Z"), firstLaunch: date("2026-01-01T10:00:00Z"), interval: .month,
                                      minutesOfDay: 600, now: date("2026-03-01T00:00:00Z"), calendar: cal)
        #expect(p.due == date("2026-02-28T10:00:00Z"))
        #expect(p.pending == [date("2026-03-03T10:00:00Z")])  // due passed, the one repeat remains
        let late = ReminderSchedule.plan(lastRun: date("2026-01-31T10:00:00Z"), firstLaunch: date("2026-01-01T10:00:00Z"), interval: .month,
                                         minutesOfDay: 600, now: date("2026-04-01T00:00:00Z"), calendar: cal)
        #expect(late.pending.isEmpty)  // then silent until the next Tidy Up run
    }

    @Test func message() {
        #expect(ReminderSchedule.message(lastRun: date("2026-11-01T18:00:00Z"), at: date("2026-11-17T10:00:00Z"), calendar: cal)
                == "Time to Tidy Up. Last run 16 days ago.")
        #expect(ReminderSchedule.message(lastRun: nil, at: Date(), calendar: cal) == "Time to Tidy Up. You haven't run it yet.")
        #expect(ReminderInterval.default == .twoWeeks && ReminderSchedule.defaultMinutes == 600)
    }
}
