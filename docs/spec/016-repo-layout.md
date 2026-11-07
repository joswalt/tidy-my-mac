# Spec 016: Repo layout and module boundaries

Ticket: [016](../planning/tickets/016-repo-layout-and-modules.md). Agreed with John, 2026-11-07. Replaces the "proposed code layout" in spec 005 §3.

## 1. Repository

- GitHub: **`joswalt/tidy-my-mac`**, private, created empty by John (no README, license or .gitignore) at https://github.com/new. Local clone: `~/Dev/tidy-my-mac`.
- No license while private; choose one if it ever goes public (rule sets reused from MIT/Apache cleaners keep their credit in `Rules/CREDITS.md`).
- The plan moves into the repo at ticket 018. Until then the wayfinder files stay in the project folder and nothing is pushed.
- Changes land through pull requests on `main`; rule changes always need John's approval (spec 006 §6).

## 2. Tree

```
tidy-my-mac/
  project.yml                 XcodeGen definition (the .xcodeproj is generated, git-ignored)
  Config/
    Identity.xcconfig         DEVELOPMENT_TEAM = 26TUUFN7M2, committed (team IDs are not secret)
    Shared.xcconfig           Swift 6, macOS 14.0, arm64 only, hardened runtime, no sandbox
  App/                        TidyMyMac app target (SwiftUI only)
    TidyMyMacApp.swift        WindowGroup + MenuBarExtra + Settings scenes
    Modules/                  one folder per sidebar module (spec 007 §2)
      SmartCare/ Health/ Cleanup/ MyClutter/ SpaceLens/
      Applications/ Performance/ Protection/ MyTools/
    MenuBar/                  menu bar popover views
    Setup/                    first-run sheet (FDA + helper)
    Shared/                   reusable views (review sheet, confirm, footer bar, badges)
    Assets.xcassets           AppIcon from design/build/a-sweep, Tidy Teal accent color
    Info.plist
    LaunchDaemons/io.github.joswalt.TidyMyMac.Helper.plist
  Helper/                     TidyMyMacHelper command-line target: main.swift only (XPC listener, wiring)
  Packages/TidyCore/          one local Swift package, library targets below
    Package.swift
    Sources/<Target>/
    Tests/<Target>Tests/
  Rules/                      bundled JSON rules + schema (spec 006 §2), copied to Contents/Resources/Rules
    schema.json  protected.json  *.json  CREDITS.md
  design/                     SVG sources, PNGs, generator scripts, style-guide.md, prototype
  docs/
    spec/README.md            the v1 build spec (index; see §6)
    spec/NNN-*.md             detailed specs (005, 006, 007, 016, ...)
    planning/                 copy of the wayfinder map, tickets and research, as history
  CLAUDE.md                   short: how to build, where the spec is, the safety rules for agents
  README.md  .gitignore
```

## 3. Targets

| Target | Kind | Depends on | Holds |
|---|---|---|---|
| `TidyMyMac` | macOS app | all TidyCore libraries except `HelperCore` | SwiftUI screens, view models, app lifecycle, `SMAppService` registration |
| `TidyMyMacHelper` | command-line tool, copied to `Contents/MacOS` | `HelperProtocol`, `HelperCore` | XPC listener and wiring only |
| `SafetyFloor` | library | none | protected floor paths, deny-list names, path normalization and validation (symlinks, bundles). Shared by app and helper so they cannot drift (spec 005 §5, 006 §5) |
| `HelperProtocol` | library | none | Codable requests/replies, operation enum, protocol version, XPC `@objc` protocol |
| `HelperCore` | library | `SafetyFloor`, `HelperProtocol` | zones, handles, operations, Trash-to-user + restore ledger; testable without XPC |
| `RuleEngine` | library | `SafetyFloor`, `RunLog` | rule model + loader (from a folder URL), schema/lint checks, matcher, sizing, dry run; Cleanup and Smart Care |
| `AppInventory` | library | `SafetyFloor`, `RuleEngine` | installed apps, leftovers, unused apps, installers, update-feed checks (ticket 013) |
| `DiskAnalysis` | library | `SafetyFloor` | Space Lens tree, Large & Old, duplicates (ticket 014) |
| `SystemTasks` | library | `HelperProtocol` | maintenance tasks, login and background items |
| `Monitors` | library | none | CPU, memory, storage, network sampling (ticket 011), FDA detection (ticket 015) |
| `RunLog` | library | none | run history and the user-side record of what went where |
| `TestSupport` | test-only library | `SafetyFloor`, `RuleEngine` | `TestHome`, snapshots, fake guards (added in milestone 1; never linked by the app) |
| `tidy-rule-lint` | command-line tool | `RuleEngine` | runs the rule loader + linter for `scripts/lint-rules.sh` (added in milestone 1) |

Rules for the split:
- UI never touches the file system directly; it calls a library.
- Libraries never import SwiftUI. Each one is unit tested on its own (test plan: ticket 017).
- The app reaches the helper only through a small client type in the app that speaks `HelperProtocol`.
- Rule files are loaded from a URL passed in: the app passes its bundled `Rules/`, tests pass the repo's `Rules/` (located via `#filePath`).

## 4. Process model

- Two programs: the app and the root helper. No third one.
- The **menu bar extra** is a `MenuBarExtra` scene in the app. When the menu bar item is on, the app stays running after its last window closes; "Open at login" uses `SMAppService.mainApp`.

## 5. Toolchain

- **XcodeGen** (`brew install xcodegen`) generates the project from `project.yml`; build with `xcodegen && xcodebuild` or in Xcode.
- Swift 6 language mode, strict concurrency, Xcode with Swift 6.4, deployment target macOS 14.0, arm64 only.
- Signing per spec 005 §9: Personal Team "Apple Development", hardened runtime, never "Sign to Run Locally".
- **No third-party Swift packages** in v1. The Sparkle appcast reader is our own code.

## 6. Handoff spec format (for ticket 018)

- `docs/spec/README.md` is the single v1 build spec: scope (Keep list), architecture (this spec), safety principles, build order, and a link to each detailed spec. A builder reads it first and finds every decision through it.
- Detailed specs move to `docs/spec/` unchanged in substance; the wayfinder map, tickets and research go to `docs/planning/` as history.
- `CLAUDE.md` points to `docs/spec/README.md` and repeats the non-negotiables (clean-room, protected floor, Trash by default, dry run first).
