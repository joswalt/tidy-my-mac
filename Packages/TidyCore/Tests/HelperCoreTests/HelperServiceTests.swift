import Darwin
import Foundation
import Testing
import TestSupport
@testable import HelperCore
import HelperProtocol
import SafetyFloor

/// Spec 005 §11 cases, with zone roots in a temp folder and no root, no XPC.
/// Serialized: the helper runs one changing job at a time per process.
@Suite(.serialized)
struct HelperServiceTests {
    struct World {
        let t: TestHome
        let w: FakeHelperWorld
        let s: HelperService
    }

    func world(_ label: String, configure: (FakeHelperWorld) -> Void = { _ in }) throws -> World {
        let t = try TestHome(label)
        let w = FakeHelperWorld(t)
        configure(w)
        try t.folder(".Trash")
        return World(t: t, w: w, s: HelperService(env: w.env, callerUID: t.home.userID))
    }

    func send(_ s: HelperService, _ r: HelperRequest, auth: Bool = true, version: Int = HelperProtocol.version) throws -> HelperReply {
        let data = s.perform(HelperCoding.encode(HelperEnvelope(r, protocolVersion: version)), authorization: auth ? FakeHelperWorld.goodToken : nil)
        return try HelperCoding.decode(HelperReply.self, data)
    }

    func items(_ r: HelperReply) -> [ZoneItem] { if case .items(let i) = r { return i }; return [] }
    func results(_ r: HelperReply) -> [ItemResult] { if case .results(let i) = r { return i }; return [] }
    func name(_ i: ZoneItem) -> String { (i.displayPath as NSString).lastPathComponent }

    @Test func helloAndVersion() throws {
        let x = try world("hello")
        defer { x.t.cleanUp() }
        #expect(try send(x.s, .hello, version: 99) == .hello(protocolVersion: HelperProtocol.version, build: 42, uid: getuid()))
        #expect(try send(x.s, .scan(zone: .systemCaches), version: 99) == .failure(.protocolMismatch(helper: HelperProtocol.version, app: 99)))
    }

    @Test func zoneItemRules() throws {
        let x = try world("zones") { $0.appleSigned = ["Safari.app"] }
        defer { x.t.cleanUp() }
        let w = x.w
        try w.file("/Library/Caches/com.example.cache/blob", size: 5000)
        try w.file("/Library/Caches/.hidden")
        try w.file("/Library/Logs/Example/log.txt")
        try w.file("/Library/Logs/TidyMyMac/helper.log")
        for n in ["system.log.0.gz", "install.log.3", "wifi.log.bz2", "system.log", "notes.txt"] { try w.file("/private/var/log/" + n) }
        try FileManager.default.createDirectory(atPath: w.root("/private/var/log/asl"), withIntermediateDirectories: true)
        try w.file("/Library/Application Support/com.example.Gone/x")
        for n in ["Apple", "Fonts", "com.apple.TCC", "TidyMyMac", "Input Methods"] { try w.file("/Library/Application Support/\(n)/x") }
        try w.file("/Library/LaunchDaemons/com.apple.thing.plist")
        try w.file("/Library/LaunchDaemons/com.example.helper.plist",
                   contents: try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.helper", "Program": "/nonexistent/helper"], format: .xml, options: 0))
        try w.file("/Applications/Safari.app/Contents/Info.plist")
        try w.file("/Applications/Vendor/Tool.app/Contents/Info.plist")
        try w.file("/Applications/Mine.app/Contents/Info.plist")

        func names(_ z: HelperZone) throws -> [String] { try items(send(x.s, .scan(zone: z))).map(name).sorted() }
        #expect(try names(.systemCaches) == ["com.example.cache"])
        #expect(try names(.systemLogs) == ["Example"])
        #expect(try names(.rotatedLogs) == ["install.log.3", "system.log.0.gz", "wifi.log.bz2"])
        // /Library/Caches is also a libraryLeftovers root (005 §5): there it goes to the Trash.
        #expect(try names(.libraryLeftovers) == ["com.example.Gone", "com.example.cache"])
        let launch = try items(send(x.s, .scan(zone: .launchItems)))
        #expect(launch.map(name) == ["com.example.helper.plist"])
        #expect(launch.first?.launchItem == LaunchItemInfo(label: "com.example.helper", program: "/nonexistent/helper", programExists: false))
        // rootApps: user-owned apps are the app's job; here every fixture app is owned by the caller.
        #expect(try names(.rootApps).isEmpty)
        #expect(try items(send(x.s, .scan(zone: .systemCaches))).first!.allocatedBytes >= 5000)
    }

    @Test func removeDeletesInDeleteZones() throws {
        let x = try world("remove")
        defer { x.t.cleanUp() }
        let p = try x.w.file("/Library/Caches/com.example.cache/blob")
        let item = try #require(items(send(x.s, .scan(zone: .systemCaches))).first)
        // Dry run changes nothing and needs no password.
        let dry = results(try send(x.s, .remove(handles: [item.handle], dryRun: true, jobID: UUID()), auth: false))
        #expect(dry.first?.outcome == .done && FileStatus.lstat(p) != nil)
        // A real run needs the admin right.
        #expect(try send(x.s, .remove(handles: [item.handle], dryRun: false, jobID: UUID()), auth: false) == .failure(.needsAuthorization))
        let real = results(try send(x.s, .remove(handles: [item.handle], dryRun: false, jobID: UUID())))
        #expect(real.first?.outcome == .done && real.first?.action == "delete")
        #expect(FileStatus.lstat(x.w.root("/Library/Caches/com.example.cache")) == nil)
        #expect(FileStatus.lstat(x.w.root("/Library/Caches")) != nil, "the zone root itself stays")
        // The handle is spent.
        #expect(results(try send(x.s, .remove(handles: [item.handle], dryRun: false, jobID: UUID()))).first?.outcome == .failed)
    }

    @Test func trashZonesMoveToTheCallersTrashWithALedger() throws {
        let x = try world("trash")
        defer { x.t.cleanUp() }
        try x.w.file("/Library/Application Support/com.example.Gone/data", size: 3000)
        let original = x.w.root("/Library/Application Support/com.example.Gone")
        let inode = FileStatus.lstat(original)!.inode
        let item = try #require(items(send(x.s, .scan(zone: .libraryLeftovers))).first)
        let r = try #require(results(try send(x.s, .remove(handles: [item.handle], dryRun: false, jobID: UUID()))).first)
        #expect(r.action == "trash" && r.outcome == .done)
        let trashPath = try #require(r.trashPath)
        #expect(PathNormalizer.isInside(trashPath, x.t.home.trash.path))
        #expect(FileStatus.lstat(trashPath)?.inode == inode, "never deleted in a trash zone; same item")

        guard case .ledger(let entries) = try send(x.s, .listTrashed) else { Issue.record("no ledger"); return }
        #expect(entries.map(\.id) == [r.ledgerID])
        // Restore round trip.
        let restored = results(try send(x.s, .restoreTrashed(ledgerIDs: [r.ledgerID!])))
        #expect(restored.first?.outcome == .done)
        #expect(FileStatus.lstat(original)?.inode == inode)
        guard case .ledger(let after) = try send(x.s, .listTrashed) else { return }
        #expect(after.isEmpty)
    }

    @Test func restoreAndEmptyRefusals() throws {
        let x = try world("ledger")
        defer { x.t.cleanUp() }
        for n in ["A", "B", "C"] { try x.w.file("/Library/Application Support/com.example.\(n)/x") }
        let all = items(try send(x.s, .scan(zone: .libraryLeftovers)))
        let rs = results(try send(x.s, .remove(handles: all.map(\.handle), dryRun: false, jobID: UUID())))
        #expect(rs.count == 3 && rs.allSatisfy { $0.outcome == .done })
        let byName = Dictionary(uniqueKeysWithValues: rs.map { (($0.path as NSString).lastPathComponent, $0) })

        // Something else now sits at A's original spot.
        try x.w.file("/Library/Application Support/com.example.A/new")
        let a = results(try send(x.s, .restoreTrashed(ledgerIDs: [byName["com.example.A"]!.ledgerID!])))
        #expect(a.first?.outcome == .skipped)
        #expect(a.first?.reason == "something else is at its original location")
        // Emptied by the user: the entry drops out of the ledger, restore says so.
        try x.t.remove(".Trash/" + (byName["com.example.C"]!.trashPath! as NSString).lastPathComponent)
        let c = results(try send(x.s, .restoreTrashed(ledgerIDs: [byName["com.example.C"]!.ledgerID!])))
        #expect(c.first?.outcome == .failed && c.first?.reason == "not in the ledger")
        // Empty one through the helper.
        let emptied = results(try send(x.s, .emptyTrashed(ledgerIDs: [byName["com.example.B"]!.ledgerID!])))
        #expect(emptied.first?.outcome == .done)
        #expect(FileStatus.lstat(byName["com.example.B"]!.trashPath!) == nil)
        // Unknown ids are refused.
        #expect(results(try send(x.s, .emptyTrashed(ledgerIDs: [UUID()]))).first?.outcome == .failed)
    }

    @Test func changesBetweenScanAndActionAreRefused() throws {
        let x = try world("swap")
        defer { x.t.cleanUp() }
        let w = x.w
        try w.file("/Library/Caches/swapped/x")
        try w.file("/Library/Caches/replaced")
        try w.file("/Library/Caches/locked/x")
        try w.file("/Library/Caches/parent-swap/x")
        try x.t.file("Documents/precious/keep.txt")
        let scanned = Dictionary(uniqueKeysWithValues: items(try send(x.s, .scan(zone: .systemCaches))).map { (name($0), $0.handle) })
        #expect(scanned.count == 4)

        try x.t.remove(absolute: w.root("/Library/Caches/swapped"))
        try FileManager.default.createSymbolicLink(atPath: w.root("/Library/Caches/swapped"), withDestinationPath: x.t.path("Documents/precious"))
        try x.t.remove(absolute: w.root("/Library/Caches/replaced"))
        try w.file("/Library/Caches/replaced", size: 10)
        guard chflags(w.root("/Library/Caches/locked/x"), UInt32(UF_IMMUTABLE)) == 0 else { Issue.record("chflags"); return }

        let rs = results(try send(x.s, .remove(handles: Array(scanned.values), dryRun: false, jobID: UUID())))
        let out = Dictionary(uniqueKeysWithValues: rs.map { (($0.path as NSString).lastPathComponent, $0) })
        #expect(out["swapped"]?.outcome == .skipped)
        #expect(out["replaced"]?.outcome == .skipped)
        #expect(out["locked"]?.outcome == .skipped)
        #expect(out["parent-swap"]?.outcome == .done)
        #expect(FileStatus.lstat(x.t.path("Documents/precious/keep.txt")) != nil)
        #expect(FileStatus.lstat(w.root("/Library/Caches/replaced"))?.size == 10)
    }

    @Test func handlesExpireAndAreNotShared() throws {
        let x = try world("expiry")
        defer { x.t.cleanUp() }
        try x.w.file("/Library/Caches/old/x")
        let h = try #require(items(try send(x.s, .scan(zone: .systemCaches))).first).handle
        // Another connection can't use it.
        let other = HelperService(env: x.w.env, callerUID: x.t.home.userID)
        #expect(results(try send(other, .remove(handles: [h], dryRun: false, jobID: UUID()))).first?.outcome == .failed)
        x.w.clock.now = x.w.clock.now.addingTimeInterval(31 * 60)
        #expect(results(try send(x.s, .remove(handles: [h], dryRun: false, jobID: UUID()))).first?.outcome == .failed)
        #expect(FileStatus.lstat(x.w.root("/Library/Caches/old")) != nil)
    }

    @Test func launchItemsAreBootedOutBeforeTrashing() throws {
        let x = try world("launch")
        defer { x.t.cleanUp() }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.agent", "Program": "/nonexistent"], format: .xml, options: 0)
        try x.w.file("/Library/LaunchAgents/com.example.agent.plist", contents: plist)
        try x.w.file("/Library/LaunchDaemons/com.example.daemon.plist",
                     contents: try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.daemon", "Program": "/nonexistent"], format: .xml, options: 0))
        let all = items(try send(x.s, .scan(zone: .launchItems)))
        _ = try send(x.s, .remove(handles: all.map(\.handle), dryRun: false, jobID: UUID()))
        let calls = x.w.commands.calls.map { $0.joined(separator: " ") }
        #expect(calls.contains("/bin/launchctl bootout gui/\(x.t.home.userID)/com.example.agent"))
        #expect(calls.contains("/bin/launchctl bootout system/com.example.daemon"))
    }

    @Test func operationsOnlyActOnValuesTheHelperReadItself() throws {
        let x = try world("ops") { w in
            w.commands.outputs["/usr/bin/tmutil listlocalsnapshots /"] = CommandOutput(status: 0, stdout: "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-07-101010.local\n")
            w.commands.outputs["/usr/sbin/pkgutil --pkgs"] = CommandOutput(status: 0, stdout: "com.apple.pkg.Core\ncom.example.tool\n")
        }
        defer { x.t.cleanUp() }
        #expect(try send(x.s, .listLocalSnapshots) == .snapshots(["2026-11-07-101010"]))
        #expect(try send(x.s, .listPackageReceipts) == .receipts(["com.example.tool"]))
        #expect(try send(x.s, .deleteLocalSnapshot(date: "2026-01-01-000000", dryRun: false)) == .failure(.notAllowed("no Time Machine snapshot 2026-01-01-000000")))
        #expect(try send(x.s, .deleteLocalSnapshot(date: "2026-11-07-101010", dryRun: false)) == .ok)
        #expect(try send(x.s, .forgetReceipt(packageID: "com.apple.pkg.Core", dryRun: false)) == .failure(.notAllowed("com.apple.pkg.Core is not a removable package receipt")))
        #expect(try send(x.s, .forgetReceipt(packageID: "com.example.tool", dryRun: false)) == .ok)
        #expect(try send(x.s, .reindexSpotlight(volumeUUID: "NOPE", dryRun: false)) == .failure(.notAllowed("not a mounted local volume")))
        #expect(try send(x.s, .reindexSpotlight(volumeUUID: "UUID-DATA", dryRun: false)) == .ok)
        #expect(try send(x.s, .flushDNS, auth: false) == .ok)
        let calls = x.w.commands.calls.map { $0.joined(separator: " ") }
        for expected in ["/usr/bin/tmutil deletelocalsnapshots 2026-11-07-101010", "/usr/sbin/pkgutil --forget com.example.tool",
                         "/usr/bin/mdutil -E /", "/usr/bin/dscacheutil -flushcache", "/usr/bin/killall -HUP mDNSResponder"] {
            #expect(calls.contains(expected), "\(expected) not run")
        }
        #expect(!calls.contains { $0.contains("com.apple.pkg.Core") && $0.contains("--forget") })
        #expect(x.w.commands.calls.allSatisfy { $0[0].hasPrefix("/") }, "absolute paths only")
    }
}
