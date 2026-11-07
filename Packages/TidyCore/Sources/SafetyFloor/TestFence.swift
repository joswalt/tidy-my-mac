import Foundation

/// A process-wide extra fence for tests (spec 017 §2.5): while any fixture root is registered,
/// the remover refuses to unlink or move anything outside those roots. Only `TestHome`
/// registers roots, so the fence is empty (and inactive) in the shipping app.
public enum TestFence {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var roots: [String: Int] = [:]

    public struct Violation: Error, CustomStringConvertible {
        public let path: String
        public var description: String { "test fence: refusing to touch \(path) outside the fixture" }
    }

    public static func register(_ root: String) {
        lock.withLock { roots[root, default: 0] += 1 }
    }

    public static func unregister(_ root: String) {
        lock.withLock {
            roots[root, default: 1] -= 1
            if roots[root] == 0 { roots[root] = nil }
        }
    }

    public static var isActive: Bool { lock.withLock { !roots.isEmpty } }

    /// Throws when the fence is active and `path` is not inside a registered root.
    public static func check(_ path: String) throws {
        let current = lock.withLock { Array(roots.keys) }
        guard !current.isEmpty else { return }
        guard let n = PathNormalizer.normalize(path),
              current.contains(where: { PathNormalizer.isInside(n, $0) }) else {
            throw Violation(path: path)
        }
    }
}
