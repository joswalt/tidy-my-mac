import CryptoKit
import Foundation
import SafetyFloor

/// A manifest of every path under a folder: inode, size, mtime, flags and a content hash
/// (spec 017 §4.1 step 2). Used to prove a run changed exactly what it should.
public struct Snapshot: Sendable {
    public struct Entry: Hashable, Sendable {
        public let identity: ItemIdentity
        public let size: Int64
        public let modified: Date
        public let flags: UInt32
        public let mode: UInt16
        public let contentHash: String?
        public let linkTarget: String?
    }

    public let root: String
    public let entries: [String: Entry]

    public init(of root: String) {
        self.root = root
        var entries: [String: Entry] = [:]
        func walk(_ path: String, _ rel: String) {
            guard let st = FileStatus.lstat(path) else { return }
            var hash: String?
            var target: String?
            if st.isRegularFile, let data = FileManager.default.contents(atPath: path) {
                hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
            if st.isSymlink { target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) }
            if !rel.isEmpty {
                entries[rel] = Entry(identity: st.identity, size: st.size, modified: st.modified, flags: st.flags,
                                     mode: st.mode, contentHash: hash, linkTarget: target)
            }
            if st.isDirectory {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] {
                    walk(path + "/" + name, rel.isEmpty ? name : rel + "/" + name)
                }
            }
        }
        walk(root, "")
        self.entries = entries
    }

    public var paths: Set<String> { Set(entries.keys) }
}
