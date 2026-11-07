import Foundation
import Testing
import TestSupport
@testable import RuleEngine
import SafetyFloor

/// Spec 006 §6 step 2: every rule has a fake tree it must match and one it must not.
struct RuleFixtureTests {
    struct Spec: Decodable {
        struct Create: Decodable {
            let path: String?
            let size: Int?
            let symlink: String?
            let to: String?
            let plistProgram: String?
        }
        let create: [Create]
        let running: [String]?
        let mustMatch: [String]
        let mustNotMatch: [String]
    }

    static let specs: [String: Spec] = {
        let data = try! Data(contentsOf: fixtures.appendingPathComponent("rule-fixtures.json"))
        return try! JSONDecoder().decode([String: Spec].self, from: data)
    }()

    static let rules: [CleanRule] = try! RuleLoader.load(from: RepoPaths.rules, version: 1).cleanRules

    @Test func everyFileRuleHasFixtures() {
        for rule in Self.rules where rule.action != .operation && rule.privilege == .user {
            let spec = Self.specs[rule.id]
            #expect(spec != nil, "\(rule.id) has no fixture")
            #expect(!(spec?.mustMatch.isEmpty ?? true) && !(spec?.mustNotMatch.isEmpty ?? true), "\(rule.id) needs both lists")
        }
    }

    @Test(arguments: rules.filter { $0.action != .operation && $0.privilege == .user }.map(\.id))
    func ruleMatchesItsFixture(_ id: String) throws {
        let rule = try #require(Self.rules.first { $0.id == id })
        let spec = try #require(Self.specs[id])
        let t = try TestHome("rule-\(id)")
        defer { t.cleanUp() }
        for c in spec.create {
            if let link = c.symlink, let to = c.to {
                try t.symlink(link, to: t.path(to))
            } else if let p = c.path {
                if let program = c.plistProgram {
                    let plist: [String: Any] = ["Label": (p as NSString).lastPathComponent, "Program": t.path(program)]
                    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                    try t.file(p, contents: data)
                } else {
                    try t.file(p, size: c.size ?? 64)
                }
            }
        }
        let scanner = RuleScanner(home: t.home, floor: ProtectedFloor(home: t.home),
                                  guards: FakeGuards(running: Set(spec.running ?? [])), hasFullDiskAccess: true)
        let result = scanner.scan(rule)
        #expect(result.state == .scanned)
        let found = Set(result.candidates.map { relative($0.path, t) })
        for m in spec.mustMatch { #expect(found.contains(m), "\(id) should match \(m); found \(found)") }
        for m in spec.mustNotMatch { #expect(!found.contains(m), "\(id) must not match \(m)") }
        for c in result.candidates { #expect(!c.selectedByDefault, "experimental rules are never ticked") }
    }
}

func relative(_ path: String, _ t: TestHome) -> String {
    let root = PathNormalizer.realPath(t.home.root.path)!
    return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
}
