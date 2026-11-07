// tidy-rule-lint <Rules folder>: loads every rule file and runs the full rule lint
// (spec 006 §6 step 1). Exit code 1 on any problem.
import Foundation
import RuleEngine
import SafetyFloor

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: tidy-rule-lint <Rules folder>\n".utf8))
    exit(2)
}
// A synthetic home: the linter only expands and compares paths, it never reads the real home.
let tmp = FileManager.default.temporaryDirectory
let home = Home(root: tmp.appendingPathComponent("tidy-lint-home"), temporaryDirectory: tmp,
                userCacheDirectory: tmp.appendingPathComponent("tidy-lint-cache"), userID: 501)
do {
    let set = try RuleLoader.load(from: URL(fileURLWithPath: args[1]), version: 0)
    let issues = RuleLinter(home: home).lint(set)
    for issue in issues { print("lint-rules: \(issue)") }
    let count = set.cleanRules.count + set.leftoverLocations.count + set.protectRules.count + set.appOverrides.count
    if issues.isEmpty {
        print("lint-rules: OK (\(count) rules)")
    } else {
        print("lint-rules: FAILED (\(issues.count) problem(s))")
        exit(1)
    }
} catch {
    print("lint-rules: \(error)")
    exit(1)
}
