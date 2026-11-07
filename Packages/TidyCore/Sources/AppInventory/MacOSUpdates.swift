import Foundation

/// macOS updates, check only (spec 013 §5). Never `--install` or `--download`.
public enum MacOSUpdates {
    /// Read-only system paths (allowed literals for the safety lint: nothing here removes files).
    public static let softwareUpdatePlist = "/Library/Preferences/com.apple.SoftwareUpdate.plist"
    public static let softwareUpdateTool = "/usr/sbin/softwareupdate"
    /// System Settings › General › Software Update (verified at first build, 017 §7).
    public static let settingsURL = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    /// Until the first-build timing check sets 3 × the slowest run (min 60 s).
    public static let listTimeout: TimeInterval = 120

    public struct Update: Sendable, Equatable, Hashable {
        public let label: String
        public let title: String
    }

    public enum Passive: Sendable, Equatable {
        case updates([Update])
        case unknown
    }

    /// The passive read of the SoftwareUpdate preferences (undocumented; "Unknown" if odd).
    public static func readPlist(at path: String = softwareUpdatePlist) -> Passive {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return .unknown }
        guard let list = dict["RecommendedUpdates"] as? [[String: Any]] else {
            if let n = dict["LastRecommendedUpdatesAvailable"] as? Int, n == 0 { return .updates([]) }
            return .unknown
        }
        return .updates(list.compactMap { u in
            let label = u["Identifier"] as? String ?? u["Product Key"] as? String ?? ""
            let title = u["Display Name"] as? String ?? label
            let version = u["Display Version"] as? String
            guard !title.isEmpty else { return nil }
            return Update(label: label, title: version.map { "\(title) \($0)" } ?? title)
        })
    }

    /// Parses `softwareupdate --list` output: `* Label:` lines with their following `Title:` lines.
    public static func parseList(_ output: String) -> [Update] {
        var out: [Update] = []
        var label: String?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("* Label:") {
                if let l = label { out.append(Update(label: l, title: l)) }
                label = line.dropFirst("* Label:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Title:"), let l = label {
                let rest = line.dropFirst("Title:".count)
                let title = rest.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? l
                let version = rest.components(separatedBy: "Version:").dropFirst().first?
                    .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
                out.append(Update(label: l, title: version.map { title.contains($0) ? title : "\(title) \($0)" } ?? title))
                label = nil
            }
        }
        if let l = label { out.append(Update(label: l, title: l)) }
        return out
    }

    public enum ListError: Error, Equatable, CustomStringConvertible {
        case timedOut(TimeInterval)
        case failed(String)
        public var description: String {
            switch self {
            case .timedOut(let s): "softwareupdate didn't answer within \(Int(s)) seconds"
            case .failed(let why): "softwareupdate failed: \(why)"
            }
        }
    }

    /// Runs `softwareupdate --list` as the user (no root), off the caller's thread, with a timeout.
    /// `tool` and `arguments` are only changed by tests (a stand-in that hangs).
    public static func list(timeout: TimeInterval = listTimeout, tool: String = softwareUpdateTool,
                            arguments: [String] = ["--list"]) async throws -> [Update] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[Update], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = arguments
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                let done = DispatchSemaphore(value: 0)
                p.terminationHandler = { _ in done.signal() }
                do { try p.run() } catch { cont.resume(throwing: ListError.failed("\(error)")); return }
                // Read both pipes while waiting so a full pipe can't stall the tool.
                let stdout = DataBox(), stderr = DataBox()
                let group = DispatchGroup()
                group.enter(); DispatchQueue.global().async { stdout.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter(); DispatchQueue.global().async { stderr.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                if done.wait(timeout: .now() + timeout) == .timedOut {
                    p.terminate()
                    cont.resume(throwing: ListError.timedOut(timeout))
                    return
                }
                group.wait()
                let text = (String(data: stdout.data, encoding: .utf8) ?? "") + "\n" + (String(data: stderr.data, encoding: .utf8) ?? "")
                if p.terminationStatus != 0 && parseList(text).isEmpty {
                    cont.resume(throwing: ListError.failed(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    cont.resume(returning: parseList(text))
                }
            }
        }
    }
}

/// Written once by one reader thread, read after `group.wait()`.
private final class DataBox: @unchecked Sendable { var data = Data() }
