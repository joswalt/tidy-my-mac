import Darwin
import Foundation
import SafetyFloor

// Monitor sources for the menu bar and Health (spec 011 §2). All public APIs, no root, no
// entitlement. The math is split from the system calls so tests can feed numbers.

/// Namespace marker for the Monitors library.
public enum Monitors {
    public static let moduleName = "Monitors"
}

// MARK: - CPU

/// Cumulative CPU ticks from `host_statistics(HOST_CPU_LOAD_INFO)`.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }

    /// Busy share between two samples, 0…1. Nil when no time passed or the counters went back.
    public static func usage(from a: CPUTicks, to b: CPUTicks) -> Double? {
        guard b.total > a.total, b.busy >= a.busy else { return nil }
        return min(1, Double(b.busy - a.busy) / Double(b.total - a.total))
    }

    public static func read() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }
}

// MARK: - Memory

public enum MemoryPressure: Int, Sendable, Comparable {
    case normal = 1, warning = 2, critical = 4

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self { case .normal: "Normal"; case .warning: "Warning"; case .critical: "Critical" }
    }

    /// `kern.memorystatus_vm_pressure_level` reports 1, 2 or 4.
    public init?(sysctlLevel: Int32) { self.init(rawValue: Int(sysctlLevel)) }
}

public struct MemorySample: Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: MemoryPressure?
    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure?) {
        self.usedBytes = usedBytes; self.totalBytes = totalBytes; self.pressure = pressure
    }

    /// Used = (internal − purgeable) + wired + compressor pages (spec 011 §2), like Activity Monitor.
    public static func usedBytes(internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressor: UInt64, pageSize: UInt64) -> UInt64 {
        ((internalPages > purgeable ? internalPages - purgeable : 0) + wired + compressor) * pageSize
    }

    public static func read() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = usedBytes(internalPages: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                             wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count),
                             pageSize: UInt64(pageSize))
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        return MemorySample(usedBytes: used, totalBytes: total, pressure: readPressure())
    }

    /// Nil if the sysctl isn't readable (spec 011 §7); callers then use `MemoryPressureWatcher`.
    public static func readPressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return MemoryPressure(sysctlLevel: level)
    }
}

/// Fallback pressure source: memory-pressure dispatch events (spec 011 §7).
public final class MemoryPressureWatcher: @unchecked Sendable {
    private let source: DispatchSourceMemoryPressure
    private let lock = NSLock()
    private var level: MemoryPressure = .normal

    public init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let e = self.source.data
            let l: MemoryPressure = e.contains(.critical) ? .critical : (e.contains(.warning) ? .warning : .normal)
            self.lock.withLock { self.level = l }
        }
        source.resume()
    }

    deinit { source.cancel() }

    public var current: MemoryPressure { lock.withLock { level } }
}

// MARK: - Storage

public struct StorageSample: Equatable, Sendable {
    /// "Available" as Finder shows it (important-usage capacity, includes purgeable space).
    public var availableBytes: Int64
    /// Free without counting purgeable space.
    public var freeBytes: Int64
    public var totalBytes: Int64
    public init(availableBytes: Int64, freeBytes: Int64, totalBytes: Int64) {
        self.availableBytes = availableBytes; self.freeBytes = freeBytes; self.totalBytes = totalBytes
    }

    /// Space macOS can reclaim on its own; shown read-only (build spec §3, Health).
    public var purgeableBytes: Int64 { max(0, availableBytes - freeBytes) }
    public var usedFraction: Double { totalBytes > 0 ? Double(totalBytes - availableBytes) / Double(totalBytes) : 0 }

    /// Reads a volume's capacities (the startup disk is `URL(fileURLWithPath: "/")`).
    public static func read(volume: URL) -> StorageSample? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey]
        guard let v = try? volume.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity,
              let important = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return StorageSample(availableBytes: important, freeBytes: Int64(v.volumeAvailableCapacity ?? Int(important)), totalBytes: Int64(total))
    }
}

// MARK: - Network

/// 64-bit byte counters summed over physical interfaces (spec 011 §2).
public struct NetworkCounters: Equatable, Sendable {
    public var inBytes: UInt64
    public var outBytes: UInt64
    public init(inBytes: UInt64, outBytes: UInt64) { self.inBytes = inBytes; self.outBytes = outBytes }

    /// Counted: up, non-loopback, physical `en*`. `utun`, `awdl`, `llw`, `bridge`, `ap`, `lo` are not,
    /// so VPN traffic isn't counted twice.
    public static func counts(interface name: String, isUp: Bool, isLoopback: Bool) -> Bool {
        isUp && !isLoopback && name.hasPrefix("en")
    }

    /// Bytes per second between two samples; a counter that went back (interface reset) gives 0.
    public static func rate(from a: NetworkCounters, to b: NetworkCounters, seconds: Double) -> (down: Double, up: Double) {
        guard seconds > 0 else { return (0, 0) }
        let d = b.inBytes >= a.inBytes ? Double(b.inBytes - a.inBytes) : 0
        let u = b.outBytes >= a.outBytes ? Double(b.outBytes - a.outBytes) : 0
        return (d / seconds, u / seconds)
    }

    /// `sysctl NET_RT_IFLIST2` (not `getifaddrs`, whose 32-bit counters wrap at 4 GB).
    public static func read() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
        var total = NetworkCounters(inBytes: 0, outBytes: 0)
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard hdr.ifm_msglen > 0 else { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(h2.ifm_index), &name) != nil {
                        let n = String(cString: name)
                        let flags = Int32(h2.ifm_flags)
                        if counts(interface: n, isUp: flags & IFF_UP != 0, isLoopback: flags & IFF_LOOPBACK != 0) {
                            total.inBytes &+= h2.ifm_data.ifi_ibytes
                            total.outBytes &+= h2.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(hdr.ifm_msglen)
            }
        }
        return total
    }
}

// MARK: - Trash size

public enum TrashSize {
    /// Allocated size of `~/.Trash` (startup volume only, spec 011 §4). Needs Full Disk Access;
    /// nil when the folder can't be listed.
    public static func measure(home: Home) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var denied = false
        guard let e = FileManager.default.enumerator(at: home.trash, includingPropertiesForKeys: keys, options: [],
                                                     errorHandler: { _, _ in denied = true; return true }) else { return nil }
        var total: Int64 = 0
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        if denied && total == 0 { return nil }
        return total
    }
}

// MARK: - Formatting (spec 011 §6)

public enum MonitorFormat {
    /// Decimal, like Finder.
    public static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// KB/s and MB/s, decimal.
    public static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1_000: "\(Int(bytesPerSecond.rounded())) B/s"
        case ..<1_000_000: "\(Int((bytesPerSecond / 1_000).rounded())) KB/s"
        default: String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
    }

    public static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}
