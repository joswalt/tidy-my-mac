import Foundation
import Testing
import TestSupport
@testable import RunLog

struct RunLogTests {
    @Test func roundTrip() throws {
        let t = try TestHome("runlog")
        defer { t.cleanUp() }
        let header = RunHeader(module: "cleanup", appVersion: "1.0 (1)", ruleSetVersion: 1, dryRun: false)
        let w = try RunLogWriter(directory: t.home.tidyRunLogs, header: header)
        try w.append(RunItem(ruleID: "cache.user.apps", path: "/x/a", allocatedBytes: 100, action: .delete, result: .done))
        try w.append(RunItem(ruleID: "dev.xcode.archives", path: "/x/b", allocatedBytes: 50, action: .trash, result: .done, trashPath: "/x/.Trash/b"))
        try w.append(RunItem(ruleID: "manual", path: "/x/c", allocatedBytes: 7, action: .trash, result: .skipped, reason: "it was replaced"))
        try w.append(RunItem(ruleID: "dev.simulators.unavailable", path: "", allocatedBytes: 0, action: .operation("simctl.deleteUnavailable"), result: .failed, reason: "x"))
        let summary = try w.finish()

        #expect(summary.done["delete"] == RunTotals(count: 1, bytes: 100))
        #expect(summary.done["trash"] == RunTotals(count: 1, bytes: 50))
        #expect(summary.skipped == RunTotals(count: 1, bytes: 7))
        #expect(summary.failed.count == 1)

        let name = w.fileURL.lastPathComponent
        #expect(name.hasSuffix("-\(header.runID.uuidString).jsonl"))
        #expect(name.range(of: #"^\d{4}-\d{2}-\d{2}T\d{6}-"#, options: .regularExpression) != nil)

        let r = try RunLogReader.read(w.fileURL)
        #expect(r.header.runID == header.runID)
        #expect(r.items.count == 4)
        #expect(r.items[1].trashPath == "/x/.Trash/b")
        #expect(r.items[3].action == .operation("simctl.deleteUnavailable"))
        #expect(!r.isInterrupted)
        #expect(RunLogReader.runs(in: t.home.tidyRunLogs).count == 1)
    }

    @Test func crashMidWrite() throws {
        let t = try TestHome("runlog-crash")
        defer { t.cleanUp() }
        let w = try RunLogWriter(directory: t.home.tidyRunLogs, header: RunHeader(module: "smartCare", appVersion: "1.0", ruleSetVersion: 1, dryRun: true))
        try w.append(RunItem(ruleID: "log.user", path: "/x/a", allocatedBytes: 1, action: .delete, result: .done))
        // Simulate a crash: a half-written line and no summary.
        let h = try FileHandle(forWritingTo: w.fileURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data(#"{"type":"item","time":"2026-11-07T10:00:00Z","ruleID":"log.us"#.utf8))
        try h.close()

        let r = try RunLogReader.read(w.fileURL)
        #expect(r.items.count == 1)
        #expect(r.isInterrupted)
        #expect(r.header.dryRun)
    }

    @Test func logIsAppendOnly() throws {
        let t = try TestHome("runlog-append")
        defer { t.cleanUp() }
        let w = try RunLogWriter(directory: t.home.tidyRunLogs, header: RunHeader(module: "cleanup", appVersion: "1.0", ruleSetVersion: 1, dryRun: false))
        var sizes: [Int] = []
        for i in 0..<3 {
            try w.append(RunItem(ruleID: "r", path: "/p\(i)", allocatedBytes: 1, action: .delete, result: .done))
            sizes.append((try FileManager.default.attributesOfItem(atPath: w.fileURL.path)[.size] as? Int) ?? 0)
        }
        #expect(sizes == sizes.sorted() && Set(sizes).count == 3)
        try w.finish()
    }
}
