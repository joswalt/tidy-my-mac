# TidyMyMac v1 build spec

**Status: signed off by John, 2026-11-07 (ticket [018](../planning/tickets/018-assemble-v1-spec.md)).**
This file becomes `docs/spec/README.md` in the repo `joswalt/tidy-my-mac` (spec 016 §6). Every link below is relative to this folder, so it works unchanged after the move. A builder reads this first; every decision is here or one link away.

---

## 1. What we are building

TidyMyMac is a native Mac cleaner with CleanMyMac-style features, built clean-room under its own name and look. v1 is for John's own Apple Silicon Macs and stays shippable later as a free direct download (not the Mac App Store).

| | |
|---|---|
| Platform | macOS 14 Sonoma or newer, Apple Silicon (arm64) only. Tested on macOS 26.7.1 |
| Stack | Swift 6 (strict concurrency), SwiftUI, XcodeGen; no third-party Swift packages |
| Bundle ID | `io.github.joswalt.TidyMyMac`; helper `io.github.joswalt.TidyMyMac.Helper` |
| Signing | John's free Personal Team "Apple Development" (team `26TUUFN7M2`), hardened runtime, no sandbox; certificate valid to 2027-11-07 |
| Install location | `/Applications/TidyMyMac.app` (required by the helper) |
| Version | 1.0; `CFBundleVersion` = integer build number = rule-set version |
| Language | English only in v1 |
| Look | Icon "Sweep", Tidy Teal accent `#0C7D75` / `#3DD9C5`, native HIG ([style guide](../../design/style-guide.md)) |

## 2. Non-negotiables (repeated in the repo's `CLAUDE.md`)

1. **Clean-room.** Never download, decompile or inspect CleanMyMac or MacPaw binaries, rules or assets. Open-source cleaners: ClearDisk, mac-cleanup-py, app-cleaner.sh, PureMac may be reused with credit; Mole, Pearcleaner, BleachBit, Latest are learn-only (spec 006 §7).
2. **Protected floor in code.** No rule, setting or hand pick can remove anything on the floor (spec 006 §5). App and helper share it through `SafetyFloor`.
3. **Trash by default.** Only caches and logs are deleted permanently; everything else goes to the Trash. Every confirm names how much goes where.
4. **Review before every removal.** One confirmation naming count, size and destination. Nothing removes files unattended: no scheduled cleaning, ever.
5. **Dry run first.** Every rule and helper operation can run report-only. New rules ship `experimental` (unticked) until a dry run on John's Mac.
6. **Every run logged** (§6.1).
7. **The helper decides what it may touch.** The app never sends the helper a path, only handles the helper issued (spec 005).
8. **No harmful or obsolete features:** no language/binary stripping, permission repair, Free RAM, periodic scripts, shredding, purgeable tricks, Wi-Fi removal (spec 005 §6.4).

## 3. Scope: v1 features

The Keep column of the [feature list](../planning/cleanmymac-feature-list.md) (53 Keep, 19 Later, 10 Drop; ticket [001](../planning/tickets/001-pick-v1-features.md)). By sidebar module ([spec 007](007-app-layout.md)):

| Module | v1 features | Detailed in |
|---|---|---|
| Tidy Up | One scan → six result cards → review sheet → one confirm → done | 007 §3, 006 §4 |
| Health | Status from six signals, storage (purgeable read-only), Trash size, setup status, run history, reminders | [012](012-health-and-reminders.md), §6.1 |
| Cleanup | User/system caches, user/system logs, Xcode junk, AI junk, local AI models (risky), iOS backups (risky), Trash bins, broken login items, ignore list | [006](006-safety-rules.md), [005](005-admin-helper.md), §6.2–6.4 |
| Declutter | Large & old files, duplicates, Downloads review, duplicate downloads | [014](014-duplicate-finder.md), §6.6–6.7 |
| Disk Map | Treemap + size-ranked list, scan one folder or volume | 007 §2, §6.8 |
| Applications | Uninstaller, unused apps, leftover files, installer leftovers, update check (Sparkle, Electron, Homebrew, macOS; check only) | 006, 005, [013](013-update-checks.md), §6.5 |
| Performance | Flush DNS, reindex Spotlight, thin Time Machine snapshots (helper), login items, background items | 005 §6, §6.9 |
| Protection | App permissions, read-only, with links to System Settings | §6.10 |
| My Tools | Launcher grid of 24 tools opening the matching module/tab | 007 §2 |
| Menu bar | CPU, memory, storage, network monitors; low-disk and full-Trash alerts | [011](011-menu-bar.md) |
| Platform | Admin helper, Full Disk Access onboarding, undo (Trash + restore) | 005, [015](015-full-disk-access.md) |

**Out of v1:** everything marked Later (malware, Cloud Cleanup, browser privacy, similar images, battery, …) and everything marked Drop. Spec 005 §13 shows how the helper-dependent Later features slot in.

## 4. Architecture

Full layout: [spec 016](016-repo-layout.md). In short:

- **Two programs.** The SwiftUI app (window + `MenuBarExtra` + Settings) and the root helper `TidyMyMacHelper` (an on-demand `SMAppService.daemon`, XPC, exits after 60 s idle).
- **One local package** `Packages/TidyCore` with nine libraries: `SafetyFloor`, `HelperProtocol`, `HelperCore`, `RuleEngine`, `AppInventory`, `DiskAnalysis`, `SystemTasks`, `Monitors`, `RunLog`. UI never touches the file system; libraries never import SwiftUI.
- **Rules** are bundled JSON in top-level `Rules/` (spec 006 §2), loaded from a URL; never downloaded.
- **Home abstraction.** All code reaches user folders through an injected `Home` value; only `App/` builds the real one (spec 017 §2).
- Repo tree additions from the test plan: spec 017 §8.

## 5. Detailed specs (all decided with John, 2026-11-07)

| Spec | Covers |
|---|---|
| [005 Admin helper](005-admin-helper.md) | Install/approval/lifecycle, 6 zones, handles, typed operations, admin auth once per run, Trash ledger + restore, signing and caller checks |
| [006 Safety rules](006-safety-rules.md) | Rule kinds, JSON format and fields, delete-vs-Trash, three risk levels, protected floor, seed rule set, review process, licences |
| [007 App layout](007-app-layout.md) | Window, sidebar, Tidy Up flow, shared patterns, menu bar, first run. Prototype: [tidymymac-layout.html](../../design/prototype/tidymymac-layout.html) |
| [011 Menu bar](011-menu-bar.md) | Monitor sources, sampling, alerts and thresholds |
| [012 Health and reminders](012-health-and-reminders.md) | Health signals and status, reminder notifications |
| [013 Update checks](013-update-checks.md) | Feed discovery, appcast parsing, version comparison, macOS updates |
| [014 Duplicate finder](014-duplicate-finder.md) | Matching, clones, scope, auto-select, cache |
| [015 Full Disk Access](015-full-disk-access.md) | Probe, grant flow, degraded mode |
| [016 Repo layout](016-repo-layout.md) | Repo, tree, targets, process model, toolchain |
| [017 Test plan](017-test-plan.md) | Guardrails, required cases, CI vs local, release gate, first-build checklist |
| [Style guide](../../design/style-guide.md) | Colour, type, layout, controls, symbols, voice, icon production |

Background (history, not instructions): the wayfinder map, tickets and research, moved to `docs/planning/`; [spike 009](../planning/spike-009/RESULTS.md) proved free signing for the helper.

## 6. Decisions settled during assembly

These filled the last gaps a builder would otherwise ask about. John signed off on all of them, 2026-11-07.

### 6.1 Run log (format left open by 005 §8 and 006 §5.7)
- One **JSON Lines** file per run: `~/Library/Application Support/TidyMyMac/RunLog/<yyyy-MM-dd'T'HHmmss>-<runID>.jsonl`. Dry runs are logged too, marked `dryRun: true`.
- Line 1 `header`: `runID` (UUID), `start`, `module` (`tidyUp`, `cleanup`, …), `appVersion`, `ruleSetVersion`, `dryRun`.
- One `item` line per item, written as it happens: `time`, `ruleID` (or `manual`), `path`, `allocatedBytes`, `action` (`trash` / `delete` / operation id), `result` (`done` / `skipped` / `failed`), `reason` on skip/fail, `trashPath` for trashed items, `helperLedgerID` for helper items.
- Last line `summary`: `end`, counts and bytes per action. A run with no summary (crash) is shown as "Interrupted"; a truncated last line is ignored (017 §4.4).
- Kept indefinitely (they are small); Settings › General has **Reveal Run Logs**. Health shows the last 50 runs; each opens a detail list.

### 6.2 Undo for items the app itself trashed
- User-level items go to the Trash with `FileManager.trashItem(at:resultingItemURL:)`; the resulting URL is logged as `trashPath`.
- Run detail offers **Restore** per item or per run: moves `trashPath` back to `path` if the item is still in the Trash and the original location is free; otherwise explains why not. Root-owned items restore through the helper's `restoreTrashed` (005 §8). Deleted caches/logs cannot be restored, and the confirm already said so.

### 6.3 Ignore list (005, 006 §6)
- `~/Library/Application Support/TidyMyMac/ignore.json`: `{ "schemaVersion": 1, "entries": [ { "kind": "path" | "ruleID", "value": "…", "added": "<date>" } ] }`.
- Added from any result row (context menu **Ignore**) or a rule's detail (**Ignore this category**); managed from the Cleanup toolbar **Ignore List…** and Settings › Cleanup. A path entry hides that item and everything inside it. It can only narrow, never widen.

### 6.4 Trash bins
- Covers `~/.Trash` and `/Volumes/*/.Trashes/<uid>` on mounted non-startup volumes the user can write. Mail's trash is **not** in v1 (`~/Library/Mail` is on the protected floor).
- Needs FDA (015 §4). Shown as one category per volume with size; always unticked in Tidy Up; permanent, so the confirm uses the red **Delete** button.
- Emptying: user-owned items with `removeItem` after floor checks; root-owned items that are in the helper ledger via `emptyTrashed`; any other root-owned item is skipped with "Empty in Finder (needs your password)".

### 6.5 Applications details not in 005/006/013
- **Uninstaller:** apps in `/Applications` (+ one vendor level) and `~/Applications`, minus Apple-signed apps and TidyMyMac. Related files from `leftover-location` rules + `app-override` + package receipts. The app must not be running (offer **Quit App**). User-owned `.app` goes to the Trash from the app; root-owned through `rootApps`.
- **Leftover files:** candidate owners are names in leftover locations that look like bundle IDs (reverse-DNS) or match a Homebrew/receipt app name and have no installed app (`NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil). Risk `caution` (unticked), grouped by the missing app. Never `com.apple.*`.
- **Unused apps:** Spotlight `kMDItemLastUsedDate`. Default "not opened in **90 days**" (choices 30 / 90 / 180 / 365). Apps with no date go in a separate "No usage date" group. Action opens the Uninstaller for the ticked apps; this tab never removes anything itself.
- **Installers:** the `installer.leftovers` rule (006 §6).

### 6.6 Large & old files
- Scope and skips are the duplicate finder's (014 §3–4), minimum size 50 MB for this list.
- Default filter: **≥ 100 MB or not modified in 1 year** (modification date, since access dates are unreliable; 004). Filters for kind (Spotlight type groups), size and age. Sizes are allocated size.
- Nothing ticked by default; removal to the Trash, rule `manual`.

### 6.7 Downloads review
- Top-level items of `~/Downloads` with size, date added, source site (`kMDItemWhereFroms`, host only), and the "Also elsewhere" duplicate flag (014 §8).
- Default filter "older than 30 days"; nothing ticked by default; Trash only.

### 6.8 Disk Map
- Default target: the home folder. Picker: Home, the startup disk (`/`), each mounted volume, **Choose Folder…**. Scanning `/` runs as the user, so unreadable folders appear as one grey "Not readable" block, never an error.
- Treemap two levels deep (squarified layout, our own code), folders coloured by kind with the accent for the selection; the size-ranked list beside it has ticks. Packages are leaves. Hard links counted once, allocated size.
- Removal to the Trash only, protected floor applies (items on it show no tick). Results cached for the session only.

### 6.9 Login items and background items (no public API for other apps' login items; 004)
- **Login Items tab:** TidyMyMac's own "Open at login" switch, plus a short explanation and **Open Login Items Settings** (`SMAppService.openSystemSettingsLoginItems()`). macOS lists other apps' modern login items only there, so v1 doesn't fake a list.
- **Background Items tab:** plists in `~/Library/LaunchAgents` (toggle with `launchctl disable|enable gui/<uid>/<label>` from the app), `/Library/LaunchAgents` (same, user domain) and `/Library/LaunchDaemons` (toggle via helper `setDaemonEnabled`). Shows label, program, vendor (from the program's code signature), loaded/disabled, program missing. Toggling is reversible and logged; removal of broken ones is Cleanup's job. `com.apple.*` never shown.

### 6.10 Protection: app permissions
- Decided (John's sign-off, 2026-11-07): list each privacy area (Camera, Microphone, Screen & System Audio Recording, Accessibility, Full Disk Access, Input Monitoring, Automation, Location Services, Files & Folders) with a one-line explanation and a button to its System Settings pane; no per-app list (TCC.db is private and moved in macOS 27). Tidy Up's Protection card then reads "Review app permissions" instead of counts.

### 6.11 Settings window (⌘,)
| Pane | Settings |
|---|---|
| General | Show in menu bar (on), Open at login (off), Reveal Run Logs |
| Alerts | Low-disk setting 10/20/50 GB (20), Trash setting 1/5/10/20 GB (5), each alert on/off (011, 012) |
| Reminders | On (on), every week / 2 weeks / month (2 weeks), time (10:00) (012) |
| Cleanup | Ignore list, duplicate minimum size (1 MB), Clear Hash Cache, check app updates automatically (on) |
| Helper | Status, Install / Repair / Remove helper, Reset Full Disk Access entry (005 §4, 015 §5) |

Stored in `UserDefaults` (app domain), except the ignore list (§6.3).

### 6.12 Other small calls
- Hash cache for duplicates is SQLite through the system `libsqlite3` (no package), in `Application Support/TidyMyMac/Cache/`.
- The app checks it is running from `/Applications`; if not, root features show "Move TidyMyMac to Applications" (005 §3).
- Keyboard: ⌘R scan, Space Quick Look on a row, ⌘⌫ adds the selection to the review (replaces 007 §7's plain ⌫, which is too easy to hit).

## 7. Build order

Each milestone ends with a pull request John reviews; CI (017 §3) runs from milestone 0. Nothing removes a real file on John's account before milestone 2's dry run.

| # | Milestone | Done when |
|---|---|---|
| 0 | **Repo bootstrap**: `project.yml`, `Config/`, empty targets, TidyCore with 9 empty libraries, `CLAUDE.md`, CI workflow, `safety-lint.sh`, `lint-rules.sh`, specs into `docs/spec/`, planning into `docs/planning/`, app icon | App builds signed on John's Mac and opens an empty sidebar; CI green |
| 1 | **Safety core**: `SafetyFloor`, `RunLog`, `RuleEngine` (loader, lint, matcher, sizing, dry run), user-level rules, `TestHome`, end-to-end snapshot-diff test | 017 §4.1–4.2 cases pass |
| 2 | **Cleanup + Tidy Up (user level)**: Cleanup module, review sheet, confirm, run log, Health run history, restore, ignore list | Dry run on John's account looks right; real run in `tidytest` passes |
| 3 | **Helper + setup**: `HelperProtocol`, `HelperCore`, helper target, auth, ledger, FDA probe and first-run sheet, system rules, Trash bins, maintenance tasks | First-build checklist (017 §7) recorded; canary run passes |
| 4 | **Applications**: inventory, Uninstaller, leftovers, unused, installers, update checks | Dummy-app uninstall and fixture appcast tests pass; live check vs 5 apps |
| 5 | **Declutter + Disk Map** (`DiskAnalysis`) | Treemap vs `du -k`, duplicate rules tests pass |
| 6 | **Performance, Protection, Health, reminders, menu bar** (`SystemTasks`, `Monitors`) | Health signals and alerts behave as 011/012 |
| 7 | **My Tools, polish, release gate** | Full release gate (017 §6) passes; tag `v1.0` |

## 8. Before the first line of code

1. John creates the empty private repo **`joswalt/tidy-my-mac`** at https://github.com/new (no README, licence or .gitignore) and adds it to this project.
2. John confirms `xcodegen` is installed (`brew install xcodegen`) and that `security find-identity -v -p codesigning` lists his Personal Team identity (WWDR G3 intermediate present; spike 009).
3. ~~John signs off on this spec~~ Done, 2026-11-07.
4. John says go for milestone 0.

## 9. Known unknowns (checked during the build, design already covers both outcomes)

- Touch ID in the helper's password dialog (005 §11).
- Whether FDA reaches a running process and helper without restart (015, 017 §7).
- FDA and Software Update deep links on 26.7.1 (017 §7).
- `softwareupdate -l` timing → timeout (013 §5).
- `kern.memorystatus_vm_pressure_level` readability; FSEvents on `~/.Trash` (011 §7).
- Whether the helper answers a second user (`tidytest`) (017 §5).
- Whether a renewed Personal Team certificate forces helper re-approval (005 §9).
- Icon Composer `.icon` vs asset catalog on macOS 14–15 (style guide §10).
