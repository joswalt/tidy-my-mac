import Testing
@testable import RuleEngine

struct OwnerAppsTests {
    let chrome = RunningApp(bundleID: "com.google.Chrome", name: "Google Chrome", executableName: "Google Chrome", isRegular: true, pid: 1)
    let updater = RunningApp(bundleID: "com.google.GoogleUpdater", name: "GoogleUpdater", isRegular: false, pid: 2)
    let codexBar = RunningApp(bundleID: "com.steipete.codexbar", name: "CodexBar", executableName: "CodexBar", isRegular: false, pid: 3)
    let fork = RunningApp(bundleID: "io.github.someone.Tool", name: "Tool", isRegular: true, pid: 4)

    func owners(_ name: String, _ apps: [RunningApp]) -> [String] { OwnerApps.owners(of: name, among: apps).map(\.name) }

    @Test func bundleID() {
        #expect(owners("com.google.Chrome", [chrome]) == ["Google Chrome"])
        #expect(owners("COM.GOOGLE.CHROME", [chrome]) == ["Google Chrome"])
        #expect(owners("com.google.Chrome.helper", [chrome]) == ["Google Chrome"])
        #expect(owners("com.google.Chromebook", [chrome]).isEmpty)
    }

    @Test func appOrExecutableName() {
        #expect(owners("CodexBar", [codexBar]) == ["CodexBar"])
        #expect(owners("Google Chrome", [chrome]) == ["Google Chrome"])
        #expect(owners("Codex", [codexBar]).isEmpty)
    }

    @Test func vendorFolderNeedsAnAppWithADockIcon() {
        #expect(owners("Google", [chrome, updater]) == ["Google Chrome"])
        #expect(owners("Google", [updater]).isEmpty)
        #expect(owners("github", [fork]).isEmpty)
        #expect(owners("Apple", [RunningApp(bundleID: "com.apple.Safari", name: "Safari")]).isEmpty)
        #expect(owners("go", [RunningApp(bundleID: "dev.go.Thing", name: "Thing")]).isEmpty)
    }

    @Test func nothingMatchesNothing() {
        #expect(owners("typescript", [chrome, updater, codexBar, fork]).isEmpty)
        #expect(owners("", [chrome]).isEmpty)
    }
}
