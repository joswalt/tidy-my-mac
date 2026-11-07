import Foundation

final class Service: NSObject, SpikeHelperProtocol {
    func whoAmI(reply: @escaping (String) -> Void) {
        // Root-only write: /Library/Application Support is root-owned.
        let dir = "/Library/Application Support/TidyMyMacSpike"
        let path = dir + "/proof.txt"
        var wrote = "no"
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try "written by helper at \(Date())\n".write(toFile: path, atomically: true, encoding: .utf8)
            wrote = path
        } catch { wrote = "error: \(error)" }
        reply("uid=\(getuid()) euid=\(geteuid()) wrote=\(wrote)")
    }
}

extension Service {
    func probes(reply: @escaping (String) -> Void) {
        var out: [String] = []
        // Q2: TCC-protected folders. Root alone cannot list these without Full Disk Access.
        for p in ["/Library/Application Support/com.apple.TCC"] {
            do { let n = try FileManager.default.contentsOfDirectory(atPath: p).count; out.append("FDA probe \(p): readable (\(n) items)") }
            catch { out.append("FDA probe \(p): DENIED (\((error as NSError).code))") }
        }
        // Q4: preferred Wi-Fi networks as root, no Location Services.
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        t.arguments = ["-listpreferredwirelessnetworks", "en0"]
        let pipe = Pipe(); t.standardOutput = pipe; t.standardError = pipe
        do { try t.run(); t.waitUntilExit()
             let txt = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
             let lines = txt.split(separator: "\n")
             out.append("networksetup exit=\(t.terminationStatus) lines=\(lines.count) first=\(lines.first ?? "")")
        } catch { out.append("networksetup error: \(error)") }
        reply(out.joined(separator: "\n"))
    }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
    let requirement: String
    init(requirement: String) { self.requirement = requirement }
    func listener(_ l: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        // Only accept our own app, signed by the same Apple-issued team.
        c.setCodeSigningRequirement(requirement)
        c.exportedInterface = NSXPCInterface(with: SpikeHelperProtocol.self)
        c.exportedObject = Service()
        c.resume()
        return true
    }
}

// build.sh generates TeamID.swift with the signing team. Ad hoc builds can only check the identifier.
let req = spikeTeamID == "ADHOC"
    ? "identifier \"\(appBundleID)\""
    : "identifier \"\(appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(spikeTeamID)\""
let listener = NSXPCListener(machServiceName: helperLabel)
let delegate = Delegate(requirement: req)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
