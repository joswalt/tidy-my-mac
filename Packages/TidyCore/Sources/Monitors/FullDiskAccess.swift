import Darwin
import SafetyFloor

/// Full Disk Access detection (spec 015 §1). There is no API, so it tries a real directory read
/// (`opendir`, which goes through TCC) on folders only FDA can open.
public enum FullDiskAccess {
    public enum State: Equatable, Sendable {
        case granted
        case missing
        /// Nothing testable existed; shown as "Can't tell".
        case unknown
    }

    /// The outcome of one `opendir`: success, or the errno.
    public enum OpenResult: Equatable, Sendable {
        case opened
        case failed(Int32)
    }

    public static func probePaths(_ home: Home) -> [String] {
        [home.trash.path, home.folder("Library", "Safari").path, home.folder("Library", "Mail").path]
    }

    /// The real probe.
    public static func state(home: Home) -> State {
        state(home: home, open: realOpen)
    }

    /// Testable form: `open` stands in for `opendir`.
    public static func state(home: Home, open: (String) -> OpenResult) -> State {
        var sawDenied = false
        for path in probePaths(home) {
            switch open(path) {
            case .opened: return .granted
            case .failed(let e) where e == EPERM: sawDenied = true
            case .failed: continue  // ENOENT, EACCES: not testable
            }
        }
        return sawDenied ? .missing : .unknown
    }

    static func realOpen(_ path: String) -> OpenResult {
        guard let dir = opendir(path) else { return .failed(errno) }
        closedir(dir)
        return .opened
    }
}
