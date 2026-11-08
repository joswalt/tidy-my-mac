import Darwin
import Foundation
import HelperProtocol
import SafetyFloor

/// Answers one connection's requests (spec 005 §6). Handles live per connection, so a new
/// connection can never use another's handles. One changing job runs at a time per helper.
public final class HelperService: @unchecked Sendable {
    public let env: HelperEnvironment
    public let callerUID: UInt32
    private let lock = NSLock()
    private var handles: [HelperHandle: HandleRecord] = [:]
    private var cancelled: Set<UUID> = []
    private let ledger: Ledger
    private let rules: ZoneRules
    /// Shared by every connection in the process: one changing job at a time.
    private static let jobLock = NSLock()
    /// Set by `shutdown()`; the helper's main loop exits when it is idle.
    public private(set) var shutdownRequested = false

    public init(env: HelperEnvironment, callerUID: UInt32) {
        self.env = env
        self.callerUID = callerUID
        self.ledger = Ledger(url: env.ledgerURL)
        self.rules = ZoneRules(env: env)
    }

    var callerHome: Home? { env.users.home(forUID: callerUID) }

    var floor: ProtectedFloor? { callerHome.map { ProtectedFloor(home: $0) } }

    /// Decodes, checks version and authorization, and dispatches.
    public func perform(_ envelope: Data, authorization: Data?) -> Data {
        HelperCoding.encode(handle(envelope, authorization: authorization))
    }

    func handle(_ data: Data, authorization: Data?) -> HelperReply {
        guard let envelope = try? HelperCoding.decode(HelperEnvelope.self, data) else {
            return .failure(.badRequest("unreadable request"))
        }
        // hello always answers, so the app can detect a version mismatch (005 §4.3).
        if envelope.request == .hello {
            return .hello(protocolVersion: HelperProtocol.version, build: env.build, uid: env.effectiveUID)
        }
        guard envelope.protocolVersion == HelperProtocol.version else {
            return .failure(.protocolMismatch(helper: HelperProtocol.version, app: envelope.protocolVersion))
        }
        if envelope.request.needsAuthorization && !env.authorization.isAuthorized(authorization) {
            return .failure(.needsAuthorization)
        }
        return dispatch(envelope.request)
    }

    func dispatch(_ request: HelperRequest) -> HelperReply {
        switch request {
        case .hello:
            return .hello(protocolVersion: HelperProtocol.version, build: env.build, uid: env.effectiveUID)
        case .shutdown:
            shutdownRequested = true
            return .ok
        case .cancel(let id):
            lock.withLock { _ = cancelled.insert(id) }
            return .ok
        case .scan(let zone):
            return .items(scan(zone))
        case .listTrashed:
            return .ledger(ledger.entries().filter { $0.callerUID == callerUID })
        case .listLocalSnapshots:
            return listSnapshots().map { .snapshots($0) } ?? .failure(.commandFailed("tmutil listlocalsnapshots"))
        case .listPackageReceipts:
            return listReceipts().map { .receipts($0) } ?? .failure(.commandFailed("pkgutil --pkgs"))
        case .spotlightStatus:
            return .volumes(volumes())
        case .flushDNS:
            return exclusive {
                guard run("/usr/bin/dscacheutil", ["-flushcache"]) != nil else { return .failure(.commandFailed("dscacheutil")) }
                _ = run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
                return .ok
            }
        case .remove(let hs, let dry, let job):
            return exclusive { .results(remove(hs, dryRun: dry, jobID: job)) }
        case .forgetReceipt(let id, let dry):
            return exclusive {
                guard let list = listReceipts() else { return .failure(.commandFailed("pkgutil --pkgs")) }
                guard list.contains(id), !DenyList.isAppleItem(id) else { return .failure(.notAllowed("\(id) is not a removable package receipt")) }
                if dry { return .ok }
                return run("/usr/sbin/pkgutil", ["--forget", id]) != nil ? .ok : .failure(.commandFailed("pkgutil --forget"))
            }
        case .reindexSpotlight(let uuid, let dry):
            return exclusive {
                guard let v = env.volumes.localVolumes().first(where: { $0.uuid == uuid }) else {
                    return .failure(.notAllowed("not a mounted local volume"))
                }
                if dry { return .ok }
                return run("/usr/bin/mdutil", ["-E", v.mountPoint], timeout: 600) != nil ? .ok : .failure(.commandFailed("mdutil -E"))
            }
        case .deleteLocalSnapshot(let date, let dry):
            return exclusive {
                guard let list = listSnapshots() else { return .failure(.commandFailed("tmutil listlocalsnapshots")) }
                guard list.contains(date) else { return .failure(.notAllowed("no Time Machine snapshot \(date)")) }
                if dry { return .ok }
                return run("/usr/bin/tmutil", ["deletelocalsnapshots", date]) != nil ? .ok : .failure(.commandFailed("tmutil deletelocalsnapshots"))
            }
        case .setDaemonEnabled(let h, let enabled, let dry):
            return exclusive { setDaemon(h, enabled: enabled, dryRun: dry) }
        case .restoreTrashed(let ids):
            return exclusive { .results(restore(ids)) }
        case .emptyTrashed(let ids):
            return exclusive { .results(empty(ids)) }
        }
    }

    private func exclusive(_ body: () -> HelperReply) -> HelperReply {
        guard Self.jobLock.try() else { return .failure(.busy) }
        defer { Self.jobLock.unlock() }
        return body()
    }

    // MARK: Scanning

    func scan(_ zone: HelperZone) -> [ZoneItem] {
        guard let floor else { return [] }
        var items: [ZoneItem] = []
        var records: [HelperHandle: HandleRecord] = [:]
        let now = env.now()
        for root in env.zoneRoots[zone] ?? [] {
            guard let rootSt = FileStatus.lstat(root), rootSt.isDirectory, !rootSt.isSymlink else { continue }
            for comps in rules.entries(zone: zone, root: root) {
                var path = root
                var ids: [ItemIdentity] = []
                var last: FileStatus?
                var ok = true
                for c in comps {
                    path += "/" + c
                    guard let st = FileStatus.lstat(path), !st.isSymlink, st.device == rootSt.device else { ok = false; break }
                    ids.append(st.identity)
                    last = st
                }
                guard ok, let st = last,
                      rules.refusal(zone: zone, name: comps.last!, path: path, st: st, callerUID: callerUID, floor: floor) == nil
                else { continue }
                let measure = Self.measure(path)
                if measure.locked || measure.crossesVolume { continue }
                let launch = zone == .launchItems ? ZoneRules.launchInfo(path) : nil
                let h = HelperHandle()
                records[h] = HandleRecord(zone: zone, zoneRoot: root, components: comps, identities: ids, scanned: now,
                                          allocatedBytes: measure.bytes, launchItem: launch)
                items.append(ZoneItem(handle: h, zone: zone, displayPath: path, allocatedBytes: measure.bytes, modified: st.modified,
                                      ownerUID: st.userID, isDirectory: st.isDirectory, launchItem: launch))
            }
        }
        lock.withLock { handles.merge(records) { $1 } }
        return items
    }

    static func measure(_ path: String) -> (bytes: Int64, locked: Bool, crossesVolume: Bool) {
        guard let root = FileStatus.lstat(path) else { return (0, false, false) }
        var bytes: Int64 = 0, locked = false, crosses = false
        var seen: Set<ItemIdentity> = []
        func walk(_ p: String, _ st: FileStatus) {
            if st.device != root.device { crosses = true; return }
            if st.isLocked { locked = true }
            if !(st.linkCount > 1 && st.isRegularFile && !seen.insert(st.identity).inserted) { bytes += st.allocatedBytes }
            guard st.isDirectory else { return }
            for n in (try? FileManager.default.contentsOfDirectory(atPath: p)) ?? [] {
                if let c = FileStatus.lstat(p + "/" + n) { walk(p + "/" + n, c) }
            }
        }
        walk(path, root)
        return (bytes, locked, crosses)
    }

    // MARK: Removing

    func record(_ h: HelperHandle) -> HandleRecord? {
        lock.withLock {
            guard let r = handles[h] else { return nil }
            if env.now().timeIntervalSince(r.scanned) > HelperProtocol.handleLifetime { handles[h] = nil; return nil }
            return r
        }
    }

    /// Opens the item's parent by descriptor and re-checks the item (005 §5.3).
    /// Returns the parent fd (caller closes) and the item's stat.
    func reopen(_ r: HandleRecord) throws -> (parentFD: Int32, name: String, st: stat) {
        guard let floor else { throw SafeRemoval.Failure(message: "unknown caller") }
        var fd = SafeRemoval.openPath(r.zoneRoot)
        guard fd >= 0 else { throw SafeRemoval.Failure(message: "the zone folder can't be opened") }
        for (i, c) in r.components.enumerated() {
            guard let st = SafeRemoval.lstatAt(fd, c) else { close(fd); throw SafeRemoval.Failure(message: "the item no longer exists") }
            let id = ItemIdentity(device: st.st_dev, inode: st.st_ino)
            guard id == r.identities[i] else { close(fd); throw SafeRemoval.Failure(message: "the item was replaced since the scan") }
            if st.st_mode & S_IFMT == S_IFLNK { close(fd); throw SafeRemoval.Failure(message: "the item became a symbolic link") }
            if i == r.components.count - 1 {
                guard let fs = FileStatus.lstat(r.path),
                      rules.refusal(zone: r.zone, name: c, path: r.path, st: fs, callerUID: callerUID, floor: floor) == nil else {
                    close(fd); throw SafeRemoval.Failure(message: "the item is no longer allowed")
                }
                return (fd, c, st)
            }
            let next = SafeRemoval.openDir(fd, c)
            close(fd)
            guard next >= 0 else { throw SafeRemoval.Failure(message: "a parent folder can't be opened") }
            fd = next
        }
        close(fd)
        throw SafeRemoval.Failure(message: "empty handle")
    }

    func remove(_ hs: [HelperHandle], dryRun: Bool, jobID: UUID) -> [ItemResult] {
        var out: [ItemResult] = []
        for h in hs {
            if lock.withLock({ cancelled.contains(jobID) }) {
                out.append(ItemResult(handle: h, path: "", allocatedBytes: 0, action: "", outcome: .skipped, reason: "cancelled"))
                continue
            }
            guard let r = record(h) else {
                out.append(ItemResult(handle: h, path: "", allocatedBytes: 0, action: "", outcome: .failed, reason: "unknown or expired handle; scan again"))
                continue
            }
            let action = r.zone.action.rawValue
            func result(_ o: ItemResult.Outcome, _ reason: String? = nil, trash: String? = nil, ledger: UUID? = nil) -> ItemResult {
                ItemResult(handle: h, path: r.path, allocatedBytes: r.allocatedBytes, action: action, outcome: o, reason: reason, trashPath: trash, ledgerID: ledger)
            }
            do {
                let (fd, name, st) = try reopen(r)
                defer { close(fd) }
                try SafeRemoval.precheck(fd, name, device: st.st_dev)
                try TestFence.check(r.path)
                if dryRun { out.append(result(.done)); continue }
                switch r.zone.action {
                case .delete:
                    try SafeRemoval.removeTree(fd, name, device: st.st_dev)
                    out.append(result(.done))
                case .trash:
                    if r.zone == .launchItems, let label = r.launchItem?.label, !DenyList.isAppleItem(label) {
                        let domain = r.zoneRoot.hasSuffix("LaunchDaemons") ? "system/\(label)" : "gui/\(callerUID)/\(label)"
                        _ = try? env.commands.run("/bin/launchctl", ["bootout", domain], timeout: 30)
                    }
                    let (dest, id) = try moveToTrash(fd, name, st: st, originalPath: r.path, jobID: jobID)
                    out.append(result(.done, trash: dest, ledger: id))
                }
                lock.withLock { handles[h] = nil }
            } catch {
                out.append(result(.skipped, "\(error)"))
            }
        }
        return out
    }

    func moveToTrash(_ parentFD: Int32, _ name: String, st: stat, originalPath: String, jobID: UUID) throws -> (String, UUID) {
        guard let home = callerHome else { throw SafeRemoval.Failure(message: "unknown caller") }
        let trashFD = try openCallerTrash(home, create: true)
        defer { close(trashFD) }
        let trashDir = home.trash.path
        var n = 1
        var freeName = name
        while true {
            if n > 1 { freeName = SafeRemoval.numberedName(name, n) }
            try TestFence.check(trashDir + "/" + freeName)
            if renameatx_np(parentFD, name, trashFD, freeName, UInt32(RENAME_EXCL)) == 0 { break }
            guard errno == EEXIST, n < 10_000 else { throw SafeRemoval.Failure.errno("move to Trash") }
            n += 1
        }
        let dest = trashDir + "/" + freeName
        // Identity from the stat taken in the root-owned zone before the move, not from the
        // user-owned Trash afterwards (which a same-user process could already have swapped).
        let entry = LedgerEntry(originalPath: originalPath, trashPath: dest, ownerUID: st.st_uid, ownerGID: st.st_gid,
                                mode: st.st_mode & 0o7777, time: env.now(), jobID: jobID, callerUID: callerUID,
                                device: st.st_dev, inode: st.st_ino, fileType: st.st_mode & S_IFMT)
        try ledger.append(entry)
        return (dest, entry.id)
    }

    /// Opens the caller's ~/.Trash by descriptor, never following a symlink, and checks that it
    /// is a real folder owned by the caller. With `create`, a missing Trash is made relative to the
    /// home folder's descriptor, owned by the caller, mode 0700.
    func openCallerTrash(_ home: Home, create: Bool) throws -> Int32 {
        let homeFD = SafeRemoval.openPath(home.root.path)
        guard homeFD >= 0 else { throw SafeRemoval.Failure(message: "the home folder can't be opened") }
        defer { close(homeFD) }
        var fd = SafeRemoval.openDir(homeFD, ".Trash")
        if fd < 0, errno == ENOENT, create {
            guard mkdirat(homeFD, ".Trash", 0o700) == 0 || errno == EEXIST else { throw SafeRemoval.Failure.errno("create the Trash") }
            fd = SafeRemoval.openDir(homeFD, ".Trash")
            if fd >= 0, env.effectiveUID == 0 {
                var hs = stat()
                let gid = fstat(homeFD, &hs) == 0 ? hs.st_gid : gid_t.max
                _ = fchown(fd, callerUID, gid)
            }
        }
        guard fd >= 0 else { throw SafeRemoval.Failure(message: "the Trash can't be opened (missing or a symbolic link)") }
        var ts = stat()
        guard fstat(fd, &ts) == 0, ts.st_mode & S_IFMT == S_IFDIR, ts.st_uid == callerUID else {
            close(fd)
            throw SafeRemoval.Failure(message: "the Trash is not a folder owned by you")
        }
        return fd
    }

    /// Whether the Trash item `name` is still the object the ledger recorded.
    static func matches(_ e: LedgerEntry, _ st: stat) -> Bool {
        guard let dev = e.device, let ino = e.inode, let type = e.fileType else { return false }
        return st.st_dev == dev && st.st_ino == ino && st.st_mode & S_IFMT == type && type != S_IFLNK
    }

    // MARK: Ledger operations

    func ledgerEntries(_ ids: [UUID]) -> [UUID: LedgerEntry] {
        Dictionary(uniqueKeysWithValues: ledger.entries().filter { ids.contains($0.id) && $0.callerUID == callerUID }.map { ($0.id, $0) })
    }

    func inCallerTrash(_ path: String) -> Bool {
        guard let home = callerHome, let n = PathNormalizer.normalize(path) else { return false }
        let comps = PathNormalizer.components(n), trash = PathNormalizer.components(PathNormalizer.normalize(home.trash.path) ?? "")
        return comps.count == trash.count + 1 && Array(comps.prefix(trash.count)) == trash
    }

    /// Moves a ledger item back as root (005 §8). Everything is done by descriptor: the Trash is
    /// opened no-follow and must be the caller's own folder, the item must still be the recorded
    /// object (device, inode, type), the destination parent is opened no-follow, the rename never
    /// replaces anything, and owner and mode are set without following a symlink. Entries without
    /// a recorded identity (helpers before 1.0.1) are refused rather than restored blind.
    func restore(_ ids: [UUID]) -> [ItemResult] {
        let entries = ledgerEntries(ids)
        var done: Set<UUID> = []
        var out: [ItemResult] = []
        for id in ids {
            guard let e = entries[id] else {
                out.append(ItemResult(handle: nil, path: "", allocatedBytes: 0, action: "restore", outcome: .failed, reason: "not in the ledger"))
                continue
            }
            func r(_ o: ItemResult.Outcome, _ why: String? = nil) -> ItemResult {
                ItemResult(handle: nil, path: e.originalPath, allocatedBytes: 0, action: "restore", outcome: o, reason: why, trashPath: e.trashPath, ledgerID: id)
            }
            guard e.inode != nil, e.device != nil, e.fileType != nil else {
                out.append(r(.skipped, "it was moved by an older helper that didn't record its identity; move it back from the Trash yourself"))
                continue
            }
            guard let home = callerHome, inCallerTrash(e.trashPath) else { out.append(r(.skipped, "it is no longer in the Trash")); continue }
            do {
                try TestFence.check(e.trashPath)
                try TestFence.check(e.originalPath)
                let trashFD = try openCallerTrash(home, create: false)
                defer { close(trashFD) }
                let name = (e.trashPath as NSString).lastPathComponent
                guard let st = SafeRemoval.lstatAt(trashFD, name) else { out.append(r(.skipped, "it is no longer in the Trash")); continue }
                guard Self.matches(e, st) else { out.append(r(.skipped, "the item in the Trash was replaced since it was moved there")); continue }
                let parentFD = SafeRemoval.openPath((e.originalPath as NSString).deletingLastPathComponent)
                guard parentFD >= 0 else { out.append(r(.skipped, "the folder it came from no longer exists")); continue }
                defer { close(parentFD) }
                let dest = (e.originalPath as NSString).lastPathComponent
                guard SafeRemoval.lstatAt(parentFD, dest) == nil else { out.append(r(.skipped, "something else is at its original location")); continue }
                guard renameatx_np(trashFD, name, parentFD, dest, UInt32(RENAME_EXCL)) == 0 else {
                    if errno == EEXIST { out.append(r(.skipped, "something else is at its original location")); continue }
                    throw SafeRemoval.Failure.errno("restore")
                }
                // The Trash entry could have been swapped between the check and the rename: check
                // again where it landed (a root-owned folder now) and send it straight back if so.
                guard let landed = SafeRemoval.lstatAt(parentFD, dest), Self.matches(e, landed) else {
                    _ = renameatx_np(parentFD, dest, trashFD, name + " (replaced) \(UUID().uuidString.prefix(8))", UInt32(RENAME_EXCL))
                    out.append(r(.skipped, "the item in the Trash was replaced since it was moved there"))
                    continue
                }
                if env.effectiveUID == 0 { _ = fchownat(parentFD, dest, e.ownerUID, e.ownerGID, AT_SYMLINK_NOFOLLOW) }
                _ = fchmodat(parentFD, dest, mode_t(e.mode), AT_SYMLINK_NOFOLLOW)
                done.insert(id)
                out.append(r(.done))
            } catch {
                out.append(r(.failed, "\(error)"))
            }
        }
        try? ledger.remove(done)
        return out
    }

    func empty(_ ids: [UUID]) -> [ItemResult] {
        let entries = ledgerEntries(ids)
        var done: Set<UUID> = []
        var out: [ItemResult] = []
        for id in ids {
            guard let e = entries[id], inCallerTrash(e.trashPath) else {
                out.append(ItemResult(handle: nil, path: "", allocatedBytes: 0, action: "delete", outcome: .failed, reason: "not in the ledger"))
                continue
            }
            let bytes = Self.measure(e.trashPath).bytes
            do {
                guard let home = callerHome else { throw SafeRemoval.Failure(message: "unknown caller") }
                let fd = try openCallerTrash(home, create: false)
                defer { close(fd) }
                let name = (e.trashPath as NSString).lastPathComponent
                guard let st = SafeRemoval.lstatAt(fd, name) else { throw SafeRemoval.Failure(message: "it is no longer in the Trash") }
                // Entries from older helpers have no identity; removal stays inside the caller's own
                // Trash by descriptor, so those may still be emptied.
                if e.inode != nil, !Self.matches(e, st) {
                    throw SafeRemoval.Failure(message: "the item in the Trash was replaced since it was moved there")
                }
                try TestFence.check(e.trashPath)
                try SafeRemoval.precheck(fd, name, device: st.st_dev)
                try SafeRemoval.removeTree(fd, name, device: st.st_dev)
                done.insert(id)
                out.append(ItemResult(handle: nil, path: e.trashPath, allocatedBytes: bytes, action: "delete", outcome: .done, ledgerID: id))
            } catch {
                out.append(ItemResult(handle: nil, path: e.trashPath, allocatedBytes: bytes, action: "delete", outcome: .failed, reason: "\(error)", ledgerID: id))
            }
        }
        try? ledger.remove(done)
        return out
    }

    // MARK: Operations

    @discardableResult
    func run(_ exe: String, _ args: [String], timeout: TimeInterval = 30) -> String? {
        guard let out = try? env.commands.run(exe, args, timeout: timeout), out.status == 0 else { return nil }
        return out.stdout
    }

    /// Time Machine local snapshot dates, e.g. "2026-11-07-101010".
    func listSnapshots() -> [String]? {
        guard let out = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return nil }
        return out.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("com.apple.TimeMachine.") else { return nil }
            return s.replacingOccurrences(of: "com.apple.TimeMachine.", with: "").replacingOccurrences(of: ".local", with: "")
        }
    }

    func listReceipts() -> [String]? {
        guard let out = run("/usr/sbin/pkgutil", ["--pkgs"]) else { return nil }
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !DenyList.isAppleItem($0) }
    }

    func volumes() -> [VolumeStatus] {
        env.volumes.localVolumes().map { v in
            let s = run("/usr/bin/mdutil", ["-s", v.mountPoint])
            let enabled = s.map { $0.contains("Indexing enabled") ? true : ($0.contains("Indexing disabled") ? false : nil) } ?? nil
            return VolumeStatus(uuid: v.uuid, mountPoint: v.mountPoint, name: v.name, indexingEnabled: enabled)
        }
    }

    func setDaemon(_ h: HelperHandle, enabled: Bool, dryRun: Bool) -> HelperReply {
        guard let r = record(h), r.zone == .launchItems, r.zoneRoot.hasSuffix("LaunchDaemons") else {
            return .failure(.notAllowed("not a launch daemon from a scan"))
        }
        do {
            let (fd, _, _) = try reopen(r)
            close(fd)
        } catch {
            return .failure(.notAllowed("\(error)"))
        }
        guard let label = ZoneRules.launchInfo(r.path)?.label, !DenyList.isAppleItem(label) else {
            return .failure(.notAllowed("no usable label"))
        }
        if dryRun { return .ok }
        guard run("/bin/launchctl", [enabled ? "enable" : "disable", "system/\(label)"]) != nil else {
            return .failure(.commandFailed("launchctl"))
        }
        if enabled { _ = run("/bin/launchctl", ["bootstrap", "system", r.path]) } else { _ = run("/bin/launchctl", ["bootout", "system/\(label)"]) }
        return .ok
    }
}
