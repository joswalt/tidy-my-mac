# TidyMyMac

A native Mac cleaner (Swift 6, SwiftUI, macOS 14+, Apple Silicon only). **Read [docs/spec/README.md](docs/spec/README.md) first**: it is the v1 build spec and links every detailed spec. `docs/planning/` is history, not instructions.

## Build and test

```bash
brew install xcodegen                         # once
xcodegen generate                             # regenerate TidyMyMac.xcodeproj (git-ignored)
swift test --package-path Packages/TidyCore   # library tests
scripts/lint-rules.sh && scripts/safety-lint.sh
scripts/check-local.sh                        # everything + signed Release build + codesign checks
```

Signing: John's free Personal Team "Apple Development" (team `26TUUFN7M2`, in `Config/Identity.xcconfig`), hardened runtime, no sandbox. Never ad hoc sign ("Sign to Run Locally"): launchd refuses to start the helper. If `codesign` fails with `errSecInternalComponent`, import Apple's `AppleWWDRCAG3.cer` into the login keychain.

## Xcode plugin

Sessions may have Apple's Xcode plugin (`xcode@claude-plugins-official`): build and test schemes, read structured build issues, render SwiftUI previews, run the app and read its console, profile with xctrace. Keep Xcode open while using it.

- `TidyMyMac.xcodeproj` is generated. Never change build settings, targets or files through the plugin's Xcode tools: put them in `project.yml` and run `xcodegen generate`.
- It does not replace `swift test` for TidyCore or `scripts/check-local.sh` for the signed Release build and codesign checks.
- Running the app through it follows the same rule as everywhere: no real (non-dry) cleanup on John's account.

## Layout (spec 016)

- `App/`: SwiftUI only. `App/TidyMyMacApp.swift` is the composition root, the one place that builds real file-system values (`Home`).
- `Helper/`: the root helper's `main.swift` (XPC wiring only).
- `Packages/TidyCore/`: nine libraries (`SafetyFloor`, `HelperProtocol`, `HelperCore`, `RuleEngine`, `AppInventory`, `DiskAnalysis`, `SystemTasks`, `Monitors`, `RunLog`). Libraries never import SwiftUI; UI never touches the file system.
- `Rules/`: bundled JSON rules (spec 006), copied to `Contents/Resources/Rules`. Never downloaded.
- `design/`: icons, style guide, prototype. `scripts/`: lints and local checks. No third-party Swift packages.

## Non-negotiables (build spec §2)

1. **Clean-room.** Never download, decompile or inspect CleanMyMac or MacPaw binaries, rules or assets. Reuse with credit only from ClearDisk, mac-cleanup-py, app-cleaner.sh, PureMac; Mole, Pearcleaner, BleachBit, Latest are learn-only.
2. **Protected floor in code** (`SafetyFloor`, shared by app and helper). No rule, setting or pick can remove anything on it.
3. **Trash by default.** Only caches and logs are deleted permanently.
4. **Review before every removal**: one confirmation naming count, size and destination. Nothing removes files unattended.
5. **Dry run first.** New rules ship `experimental` until a dry run on John's Mac.
6. **Every run is logged.**
7. **The helper decides what it may touch.** The app never sends the helper a path, only handles the helper issued.
8. **No harmful or obsolete features** (language stripping, permission repair, Free RAM, shredding, …).

## Rules for agents working here

- Tests never touch the real home folder: use `TestHome` fixtures in the temp dir. Never run a real (non-dry) cleanup on John's account. The one exception is the release gate's canary run, which John does himself and which may remove only items `scripts/user-canary.sh` and `canary.sh` made.
- Reach user folders only through an injected `Home`; `scripts/safety-lint.sh` enforces this.
- Changes land through pull requests on `main`; rule changes always need John's approval.
- Work on John's Mac in a git worktree at `~/Dev/tidy-my-mac/.worktrees/<name>` (git-ignored), never in sibling folders under `~/Dev`; keep build output (DerivedData) inside that worktree. Remove the worktree after its PR merges.
- Work milestone by milestone (build spec §7); each milestone ends with a PR. GitHub issues track milestones and tasks.
