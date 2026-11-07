import Foundation
import SafetyFloor
import Testing
import TestSupport
@testable import SystemTasks

/// Scripted launchctl: records every call and answers from a table. Never runs anything.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    var answers: [String: String] = [:]
    var calls: [[String]] = []
    let lock = NSLock()
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.withLock {
            calls.append(arguments)
            return (0, answers[arguments.joined(separator: " ")] ?? "")
        }
    }
}

struct FakeSigner: ProgramSigner {
    func vendor(of program: String) -> String? { program.contains("acme") ? "Acme Inc" : nil }
}

func plist(label: String, program: String?) -> Data {
    var d: [String: Any] = ["Label": label]
    if let program { d["ProgramArguments"] = [program, "--daemon"] }
    return try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
}

struct BackgroundItemsTests {
    @Test func linkMarker() { #expect(SystemTasks.moduleName == "SystemTasks") }

    @Test func parsesLaunchctlOutput() {
        let print = """
        gui/501 = {
            type = login
            services = {
                   0      -  com.acme.agent
                 812      0  com.example.helper
            }
            unmanaged processes = {
            }
        }
        """
        #expect(BackgroundItems.loadedLabels(print) == ["com.acme.agent", "com.example.helper"])
        let disabled = """
        disabled services = {
            "com.acme.agent" => disabled
            "com.example.helper" => enabled
            "org.old.style" => true
        }
        """
        #expect(BackgroundItems.disabledLabels(disabled) == ["com.acme.agent", "org.old.style"])
        #expect(SystemProgramSigner.vendorName(fromSubject: "Developer ID Application: Acme Inc (ABCDE12345)") == "Acme Inc")
    }

    @Test func listsNonAppleItemsWithState() throws {
        let t = try TestHome("bgitems")
        defer { t.cleanUp() }
        let program = try t.file("Applications/Acme.app/Contents/MacOS/acme-agent")
        try t.file("Library/LaunchAgents/com.acme.agent.plist", contents: plist(label: "com.acme.agent", program: program.path))
        try t.file("Library/LaunchAgents/com.apple.something.plist", contents: plist(label: "com.apple.something", program: "/bin/ls"))
        try t.file("Library/LaunchAgents/notes.txt", size: 4)
        let sysAgents = try t.folder("sys/LaunchAgents")
        let sysDaemons = try t.folder("sys/LaunchDaemons")
        try plist(label: "com.example.broken", program: t.base.appendingPathComponent("missing/prog").path)
            .write(to: sysDaemons.appendingPathComponent("com.example.broken.plist"))
        let runner = FakeRunner()
        let uid = t.home.userID
        runner.answers["print gui/\(uid)"] = "services = {\n 0 - com.acme.agent\n}\n"
        runner.answers["print-disabled system"] = "\"com.example.broken\" => disabled\n"
        let items = BackgroundItems(home: t.home, systemAgents: sysAgents, systemDaemons: sysDaemons, runner: runner, signer: FakeSigner()).list()
        #expect(items.map(\.label) == ["com.acme.agent", "com.example.broken"])
        #expect(items[0].domain == .userAgent && items[0].loaded && !items[0].disabled && items[0].programExists && items[0].vendor == "Acme Inc")
        #expect(items[1].domain == .systemDaemon && !items[1].loaded && items[1].disabled && !items[1].programExists)
        // Listing only reads: print and print-disabled, nothing else.
        #expect(runner.calls.allSatisfy { $0.first == "print" || $0.first == "print-disabled" })
    }

    @Test func togglesAgentsOnlyFromTheirFolders() throws {
        let t = try TestHome("bgtoggle")
        defer { t.cleanUp() }
        let url = try t.file("Library/LaunchAgents/com.acme.agent.plist", contents: plist(label: "com.acme.agent", program: "/bin/ls"))
        let elsewhere = try t.file("Documents/com.acme.agent.plist", contents: plist(label: "com.acme.agent", program: "/bin/ls"))
        let runner = FakeRunner()
        let bg = BackgroundItems(home: t.home, systemAgents: t.base, systemDaemons: t.base, runner: runner)
        let uid = t.home.userID
        let item = BackgroundItem(label: "com.acme.agent", plistPath: url.path, domain: .userAgent, program: "/bin/ls", programExists: true)

        // Dry run changes nothing.
        #expect((try? bg.setAgent(item, enabled: false, dryRun: true).get()) != nil)
        #expect(runner.calls.isEmpty)

        #expect((try? bg.setAgent(item, enabled: false, dryRun: false).get()) != nil)
        #expect(runner.calls == [["disable", "gui/\(uid)/com.acme.agent"], ["bootout", "gui/\(uid)/com.acme.agent"]])
        runner.calls = []
        #expect((try? bg.setAgent(item, enabled: true, dryRun: false).get()) != nil)
        #expect(runner.calls == [["enable", "gui/\(uid)/com.acme.agent"], ["bootstrap", "gui/\(uid)", url.path]])

        runner.calls = []
        let outside = BackgroundItem(label: "com.acme.agent", plistPath: elsewhere.path, domain: .userAgent, program: nil, programExists: false)
        let daemon = BackgroundItem(label: "com.acme.d", plistPath: url.path, domain: .systemDaemon, program: nil, programExists: false)
        let apple = BackgroundItem(label: "com.apple.x", plistPath: url.path, domain: .userAgent, program: nil, programExists: false)
        let wrongLabel = BackgroundItem(label: "com.other", plistPath: url.path, domain: .userAgent, program: nil, programExists: false)
        if case .failure(let e) = bg.setAgent(outside, enabled: false, dryRun: false) { #expect(e == .notListed) } else { Issue.record("allowed") }
        if case .failure(let e) = bg.setAgent(daemon, enabled: false, dryRun: false) { #expect(e == .needsHelper) } else { Issue.record("allowed") }
        if case .failure(let e) = bg.setAgent(apple, enabled: false, dryRun: false) { #expect(e == .appleItem) } else { Issue.record("allowed") }
        if case .failure(let e) = bg.setAgent(wrongLabel, enabled: false, dryRun: false) { #expect(e == .notListed) } else { Issue.record("allowed") }
        #expect(runner.calls.isEmpty)
    }
}
