import Foundation
import Testing
@testable import SafetyFloor

/// Spec 017 §4.2: every floor path, its children, and case/Unicode variants are refused.
struct FloorTests {
    static let home = Home(root: URL(fileURLWithPath: "/Users/tidytest"), temporaryDirectory: URL(fileURLWithPath: "/private/var/folders/xx/T"),
                           userCacheDirectory: URL(fileURLWithPath: "/private/var/folders/xx/C"), userID: 501)
    let floor = ProtectedFloor(home: Self.home)

    @Test(arguments: [
        "/", "/System", "/System/Library/Caches/x", "/bin/ls", "/sbin/mount", "/usr", "/usr/bin/true", "/usr/local",
        "/private/var/db/receipts", "/var/db/receipts", "/Library/Apple/x", "/Library/Extensions/foo.kext",
        "/.Spotlight-V100", "/.DocumentRevisions-V100/x",
        "/Applications", "/Library", "/Users", "/Volumes", "/Volumes/External", "/Users/someone",
        "/Users/tidytest", "/Users/tidytest/Library", "/Users/tidytest/Library/Application Support",
        "/Users/tidytest/Documents", "/Users/tidytest/Documents/report.pages", "/Users/tidytest/Desktop/a.txt",
        "/Users/tidytest/Pictures/x", "/Users/tidytest/Movies/x", "/Users/tidytest/Music/x",
        "/Users/tidytest/Library/Mobile Documents/com~apple~CloudDocs/x", "/Users/tidytest/Library/CloudStorage/Dropbox",
        "/Users/tidytest/Library/Keychains/login.keychain-db", "/Users/tidytest/Library/Mail/V10",
        "/Users/tidytest/Library/Application Support/TidyMyMac/RunLog/x.jsonl", "/Users/tidytest/Library/Logs/TidyMyMac",
        "/Library/Logs/TidyMyMac/helper.log", "/Library/Application Support/TidyMyMac",
        "/Users/tidytest/Pictures/Photos Library.photoslibrary", "/Users/tidytest/Downloads/Old.photoslibrary",
        "/Applications/Foo.app/Contents/Info.plist", "/Users/tidytest/Library/Caches/Thing.app/Contents/x",
    ])
    func protectedForRules(_ path: String) {
        #expect(floor.verdict(for: path, context: .rule).isProtected, "\(path) should be protected")
    }

    @Test(arguments: [
        "/Users/tidytest/Library/Caches/com.example.App", "/Users/tidytest/Library/Logs/DiagnosticReports",
        "/Users/tidytest/Downloads/Tool.dmg", "/usr/local/lib/old.dylib", "/Library/Caches/com.example",
        "/Applications/Foo.app", "/Users/tidytest/Library/Developer/Xcode/DerivedData/App-x",
    ])
    func allowedForRules(_ path: String) {
        #expect(floor.verdict(for: path, context: .rule) == .allowed, "\(path) should be allowed")
    }

    @Test func personalFoldersAllowHandPicksInsideOnly() {
        #expect(floor.verdict(for: "/Users/tidytest/Documents/big.mov", context: .manualPick) == .allowed)
        #expect(floor.verdict(for: "/Users/tidytest/Documents", context: .manualPick).isProtected)
        #expect(floor.verdict(for: "/Users/tidytest/Library/Keychains/x", context: .manualPick).isProtected)
    }

    @Test(arguments: [
        "/users/TIDYTEST/documents/a", "/Users/tidytest/DOCUMENTS", "/Users/tidytest/./Documents/a",
        "/Users//tidytest/Documents/a", "/System/Volumes/Data/Users/tidytest/Documents/a",
        "/Users/tidytest/Library/Caches/../Keychains/x", "relative/path", "/USR/bin",
    ])
    func spellingVariantsAreRefused(_ path: String) {
        #expect(floor.verdict(for: path, context: .rule).isProtected, "\(path) should be protected")
    }

    @Test func unicodeFormsAreTheSamePath() {
        let nfcHome = Home(root: URL(fileURLWithPath: "/Users/Jos\u{00E9}"), temporaryDirectory: URL(fileURLWithPath: "/tmp"),
                           userCacheDirectory: URL(fileURLWithPath: "/tmp"), userID: 501)
        let f = ProtectedFloor(home: nfcHome)
        #expect(f.verdict(for: "/Users/Jose\u{0301}/Documents/a").isProtected)
        #expect(f.verdict(for: "/Users/Jose\u{0301}/Library/Caches/x") == .allowed)
    }

    @Test func additionsOnlyAdd() {
        let f = ProtectedFloor(home: Self.home, additions: [FloorEntry(path: "/Library/*/Apple", reason: "test")])
        #expect(f.verdict(for: "/Library/Caches/Apple").isProtected)
        #expect(f.verdict(for: "/Library/Application Support/apple/x").isProtected)
        #expect(f.verdict(for: "/Library/Caches/Other") == .allowed)
        #expect(f.entries.count == floor.entries.count + 1)
    }

    @Test func normalizer() {
        #expect(PathNormalizer.normalize("/var/folders/x") == "/private/var/folders/x")
        #expect(PathNormalizer.normalize("/tmp/a/") == "/private/tmp/a")
        #expect(PathNormalizer.normalize("/a/../b") == nil)
        #expect(PathNormalizer.normalize("a/b") == nil)
        #expect(PathNormalizer.normalize("/System/Volumes/Data/Users/x") == "/Users/x")
        #expect(PathNormalizer.normalize("/System/Volumes/Data") == "/System/Volumes/Data")
    }

    @Test func homeExpansion() {
        let h = Self.home
        #expect(h.expand("~") == "/Users/tidytest")
        #expect(h.expand("~/Library/Caches") == "/Users/tidytest/Library/Caches")
        #expect(h.expand("$TMPDIR/x") == "/private/var/folders/xx/T/x")
        #expect(h.expand("$DARWIN_USER_CACHE_DIR") == "/private/var/folders/xx/C")
        #expect(h.expand("/Library/Caches") == "/Library/Caches")
        #expect(h.expand("Library") == nil)
        #expect(h.expand("$HOME/x") == nil)
    }

    @Test func zonesAgreeWithFloor() {
        // Zone roots themselves are never removed; their children may be.
        for zone in HelperZone.allCases {
            for root in zone.roots {
                #expect(floor.verdict(for: root).isProtected, "\(root) itself must be protected")
            }
        }
        #expect(HelperZone.systemCaches.action == .delete)
        #expect(HelperZone.rootApps.action == .trash)
    }

    @Test func appleNames() {
        #expect(DenyList.isAppleItem("com.apple.Safari"))
        #expect(DenyList.isAppleItem("COM.APPLE.x"))
        #expect(!DenyList.isAppleItem("com.example.apple"))
    }
}
