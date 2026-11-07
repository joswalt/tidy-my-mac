import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import SafetyFloor

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

func lintHome() -> Home {
    let tmp = FileManager.default.temporaryDirectory
    return Home(root: tmp.appendingPathComponent("lint-home"), temporaryDirectory: tmp,
                userCacheDirectory: tmp.appendingPathComponent("lint-cache"), userID: 501)
}

/// The shipped rule set loads, lints clean and stays in step with the code.
struct ShippedRuleSetTests {
    let set: RuleSet

    init() throws { set = try RuleLoader.load(from: RepoPaths.rules, version: 1) }

    @Test func lintsClean() {
        let issues = RuleLinter(home: lintHome()).lint(set)
        #expect(issues.isEmpty, "\(issues)")
        #expect(!set.cleanRules.isEmpty)
    }

    @Test func everyRuleShipsExperimental() {
        // New rules stay unticked until a dry run on John's Mac (spec 006 §6 step 3).
        for r in set.cleanRules { #expect(r.status == .experimental, "\(r.id)") }
    }

    @Test func protectedJSONDenyNamesMatchCode() {
        // Spec 005 §5.1 / 017 §4.2: protected.json and the compiled deny list are the same names.
        let names = Set(set.protectRules.filter { $0.id.hasPrefix("protect.deny.") }
            .compactMap { $0.pattern?.split(separator: "/").last.map(String.init) })
        #expect(names == DenyList.libraryLeftoverNames)
    }

    @Test func floorAdditionsApply() {
        let home = lintHome()
        let floor = ProtectedFloor(home: home, additions: set.floorAdditions(home: home))
        for root in HelperZone.libraryLeftovers.roots {
            #expect(floor.verdict(for: root + "/Apple/x").isProtected)
            #expect(floor.verdict(for: root + "/Input Methods").isProtected)
            #expect(floor.verdict(for: root + "/com.example.Leftover") == .allowed)
        }
    }

    @Test func schemaEnumsMatchSwift() throws {
        let data = try Data(contentsOf: RepoPaths.rules.appendingPathComponent("schema.json"))
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let defs = try #require(schema["$defs"] as? [String: Any])
        let clean = try #require((defs["cleanRule"] as? [String: Any])?["properties"] as? [String: Any])
        func enumValues(_ props: [String: Any], _ key: String) -> Set<String> {
            Set(((props[key] as? [String: Any])?["enum"] as? [String]) ?? [])
        }
        #expect(enumValues(clean, "category") == Set(RuleCategory.allCases.map(\.rawValue)))
        #expect(enumValues(clean, "risk") == Set(RuleRisk.allCases.map(\.rawValue)))
        #expect(enumValues(clean, "action") == Set(RuleAction.allCases.map(\.rawValue)))
        #expect(enumValues(clean, "module") == Set(RuleModule.allCases.map(\.rawValue)))
        #expect(enumValues(clean, "zone") == Set(HelperZone.allCases.map(\.rawValue)))
        #expect(Set(clean.keys) == Set(CleanRule.CodingKeys.allCases.map(\.rawValue)))
        let target = try #require((defs["target"] as? [String: Any])?["properties"] as? [String: Any])
        #expect(Set(target.keys) == Set(RuleTarget.CodingKeys.allCases.map(\.rawValue)))
        let source = try #require((defs["source"] as? [String: Any])?["properties"] as? [String: Any])
        #expect(enumValues(source, "license") == Licence.allowed)
    }
}

/// Spec 017 §4.2: one bad rule file per lint rule must fail with the named error.
struct LintNegativeTests {
    @Test(arguments: LintIssue.Code.allCases)
    func eachLintRuleFires(_ code: LintIssue.Code) throws {
        var set = RuleSet(version: 1)
        let file = fixtures.appendingPathComponent("lint/\(code.rawValue).json")
        let folder = fixtures.appendingPathComponent("lint/\(code.rawValue)", isDirectory: true)
        if FileManager.default.fileExists(atPath: file.path) {
            try RuleLoader.loadFile(file, into: &set)
        } else {
            set = try RuleLoader.load(from: folder, version: 1)
        }
        let codes = RuleLinter(home: lintHome()).lint(set).map(\.code)
        #expect(codes.contains(code), "expected \(code), got \(codes)")
    }

    @Test(arguments: ["unknown-field", "unknown-target-field", "wrong-version", "bad-enum", "missing-keeps", "not-json"])
    func badFilesFailToLoad(_ name: String) {
        var set = RuleSet(version: 1)
        #expect(throws: RuleLoader.LoadError.self) {
            try RuleLoader.loadFile(fixtures.appendingPathComponent("load/\(name).json"), into: &set)
        }
    }

    @Test func unknownFieldNamesTheField() {
        var set = RuleSet(version: 1)
        do {
            try RuleLoader.loadFile(fixtures.appendingPathComponent("load/unknown-field.json"), into: &set)
            Issue.record("should have failed")
        } catch {
            #expect("\(error)".contains("gaurds"))
        }
    }
}
