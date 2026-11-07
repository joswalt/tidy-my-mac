---
id: 016
title: Decide the repo layout and module boundaries
type: wayfinder:grilling
status: closed
assignee: claude (thread: Plan TidyMyMac repo and modules)
blocked_by: []
---

## Question

How is the TidyMyMac codebase split (Xcode project vs Swift Package targets: app, helper, rules engine, scanners per module, menu bar extra, shared XPC protocol), where the bundled rules and assets live, which GitHub repo it goes in (John must create it), and what the final handoff spec looks like (one document vs the specs folder plus an index)?

## Resolution

Agreed with John, 2026-11-07 (all recommendations accepted). Full layout: [specs/016-repo-layout.md](../../spec/016-repo-layout.md).

- Repo: private `joswalt/tidy-my-mac`, created empty by John at https://github.com/new; plan moves in at ticket 018, nothing pushed before.
- XcodeGen `project.yml` (generated .xcodeproj ignored), committed `Config/Identity.xcconfig`.
- Thin SwiftUI app + `TidyMyMacHelper` (main.swift only) + one local package `Packages/TidyCore` with 9 libraries: SafetyFloor, HelperProtocol, HelperCore, RuleEngine, AppInventory, DiskAnalysis, SystemTasks, Monitors, RunLog.
- Rules in top-level `Rules/` copied into the app; icon from design/build/a-sweep into App/Assets.xcassets; design sources in `design/`.
- Menu bar = `MenuBarExtra` in the app process (no separate agent); open at login via `SMAppService.mainApp`.
- No third-party Swift packages; own appcast reader. Swift 6 strict concurrency, macOS 14+, arm64.
- Handoff format: `docs/spec/README.md` index + detailed specs in `docs/spec/`, wayfinder history in `docs/planning/`, root `CLAUDE.md` pointing to it.

Follow-ups: none new; ticket 017 (test plan) is unblocked, ticket 018 uses §6 of the spec.
