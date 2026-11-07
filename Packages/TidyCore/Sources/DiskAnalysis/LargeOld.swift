import Foundation
import UniformTypeIdentifiers

/// Spotlight-style type groups for the Large & Old kind filter (build spec §6.6).
public enum FileKind: String, CaseIterable, Sendable, Identifiable {
    case movies, music, pictures, archives, diskImages, documents, apps, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .movies: "Movies"
        case .music: "Music"
        case .pictures: "Pictures"
        case .archives: "Archives"
        case .diskImages: "Disk Images"
        case .documents: "Documents"
        case .apps: "Apps"
        case .other: "Other"
        }
    }

    public static func of(_ path: String) -> FileKind {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return .apps }
        if type.conforms(to: .diskImage) || ["dmg", "iso", "sparseimage", "sparsebundle", "img"].contains(ext.lowercased()) { return .diskImages }
        if type.conforms(to: .archive) || type.conforms(to: .zip) || type.conforms(to: .gzip) { return .archives }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .movies }
        if type.conforms(to: .audio) { return .music }
        if type.conforms(to: .image) { return .pictures }
        if type.conforms(to: .content) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .pdf) { return .documents }
        return .other
    }
}

/// Large & Old (build spec §6.6): the list holds files of 50 MB or more; the default filter shows
/// those of 100 MB or more, or not modified in a year. Sizes are allocated sizes.
public struct LargeOldFilter: Sendable, Equatable {
    /// The smallest file the list ever holds.
    public static let listMinimum: Int64 = 50 * 1_000_000

    public enum Match: String, CaseIterable, Sendable, Identifiable {
        case either, both
        public var id: String { rawValue }
        public var title: String { self == .either ? "Large or old" : "Large and old" }
    }

    public var minimumSize: Int64
    /// nil: any age.
    public var olderThanDays: Int?
    public var match: Match
    public var kinds: Set<FileKind>

    public init(minimumSize: Int64 = 100 * 1_000_000, olderThanDays: Int? = 365, match: Match = .either,
                kinds: Set<FileKind> = Set(FileKind.allCases)) {
        self.minimumSize = minimumSize
        self.olderThanDays = olderThanDays
        self.match = match
        self.kinds = kinds
    }

    public static let `default` = LargeOldFilter()

    public func isOld(_ f: FileEntry, now: Date) -> Bool {
        guard let days = olderThanDays else { return false }
        return f.modified < now.addingTimeInterval(-Double(days) * 86_400)
    }

    public func matches(_ f: FileEntry, now: Date = Date()) -> Bool {
        guard f.allocatedBytes >= Self.listMinimum, kinds.contains(FileKind.of(f.path)) else { return false }
        let large = f.allocatedBytes >= minimumSize
        guard olderThanDays != nil else { return large }
        let old = isOld(f, now: now)
        return match == .either ? (large || old) : (large && old)
    }

    public func apply(_ files: [FileEntry], now: Date = Date()) -> [FileEntry] {
        files.filter { matches($0, now: now) }.sorted { ($0.allocatedBytes, $0.path) > ($1.allocatedBytes, $1.path) }
    }
}
