# 003 — Open-source Mac cleaner/uninstaller rule sets for TidyMyMac

**Question:** Which open-source Mac cleaner/uninstaller projects have reusable cleanup or uninstall rule sets that TidyMyMac (a personal SwiftUI Mac cleaner) could learn from or reuse?

**Policy applied:** MIT / BSD / Apache-2.0 → OK to copy with credit. GPL → learn from only, do not copy. Anything else is called out.

**Method:** Each repo was shallow-cloned from GitHub on 2026-11-07. Licenses were read from the LICENSE/COPYING file in the repo, and rule locations from the source tree. "Last commit" is the HEAD commit date on the default branch on 2026-11-07 unless noted. CleanMyMac was not downloaded or inspected.

---

## Summary table

| # | Project | License (exact, from repo) | Rules live in | Format | Last commit | Policy verdict |
|---|---|---|---|---|---|---|
| 1 | [momenbasel/PureMac](https://github.com/momenbasel/PureMac) | MIT | `PureMac/Logic/Scanning/Conditions.swift`, `Locations.swift`, `Services/ScanEngine.swift`, `Logic/Utilities/ProviderPaths.swift` | Swift arrays/structs | 2026-11-06 | **Copy with credit**, but see the provenance note below |
| 2 | [bysiber/cleardisk](https://github.com/bysiber/cleardisk) | MIT | `Sources/ClearDisk/DiskMonitor.swift` (`allCachePaths()`, `cacheDescriptions`), `AppCacheCatalog.swift` | Swift tuples `(name, icon, path, riskLevel, group)` + descriptions | 2026-09-10 | **Copy with credit** |
| 3 | [mac-cleanup/mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) | Apache-2.0 | `mac_cleanup/default_modules.py` | Python functions, each adds `Path(glob)` / `Command(...)` | 2026-10-26 | **Copy with credit** (keep Apache notice) |
| 4 | [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) | **Apache 2.0 with Commons Clause** (not plain Apache) | `Pearcleaner/Logic/Conditions.swift`, `Locations.swift`, `AppPathsFetch.swift`, `ReversePathsFetch.swift` | Swift structs (`Condition`, `SkipCondition`) and path arrays | 2026-06-22; rule files last changed 2025-12-11; README says **"Project Status: On Hold"** | **Learn from.** Copying is allowed only if TidyMyMac is never sold, and the Commons Clause notice must go with the credit. Plain-Apache policy does not cover it. |
| 5 | [tw93/Mole](https://github.com/tw93/Mole) | GPL-3.0 | `lib/clean/*.sh` (user, app_caches, dev, system, caches, brew…), `lib/core/app_protection.sh` + `app_protection_data.sh`, `lib/uninstall/*.sh` | Bash (`safe_clean <path> "<label>"` calls; data-only bundle-ID arrays) | 2026-11-07 (very active) | **Learn only** |
| 6 | [bleachbit/bleachbit](https://github.com/bleachbit/bleachbit) | GPL-3.0-or-later (incl. cleaner definitions) | `cleaners/*.xml` (110 files); schema `doc/cleaner_markup_language.xsd` | CleanerML XML | 2026-11-06 | **Learn only** |
| 7 | [bleachbit/cleanerml](https://github.com/bleachbit/cleanerml) | GPL-3.0 | `release/`, `pending/` | CleanerML XML | 2026-10-24 | **Learn only** |
| 8 | [sunknudsen/privacy-guides — app-cleaner.sh](https://github.com/sunknudsen/privacy-guides/tree/main/archive/how-to-clean-uninstall-macos-apps-using-appcleaner-open-source-alternative) | MIT | `archive/how-to-clean-uninstall-macos-apps-using-appcleaner-open-source-alternative/app-cleaner.sh` | Bash list of ~27 `Library` locations + `find -iname "*name*"/"*bundleid*"` | Script last changed 2025-05-11 (in an `archive/` folder) | **Copy with credit** |
| 9 | [tbillington/kondo](https://github.com/tbillington/kondo) | MIT | `kondo-lib/src/lib.rs` | Rust consts: marker file → artifact dirs | 2026-01-28 | **Copy with credit** (project build artifacts only) |
| 10 | [fwartner/mac-cleanup](https://github.com/fwartner/mac-cleanup) | MIT | `mac-cleanup` (483-line bash) | Bash `rm -rf` lines | 2023-05-21 (stale) | Copy with credit, but outdated |
| 11 | [Kevin-De-Koninck/Clean-Me](https://github.com/Kevin-De-Koninck/Clean-Me) | MIT | `Clean Me/Paths.swift` | Swift string constants | 2021-02-05 (stale) | Copy with credit, but outdated |

Not investigated: Freemacsoft AppCleaner, which is freeware and not open source. Pearcleaner's README credits it as inspiration.

---

## Per-project detail

### 1. PureMac (MIT): SwiftUI, closest to TidyMyMac's stack
- **License:** `MIT License, Copyright (c) 2026 PureMac Contributors` (LICENSE).
- **Rules:**
  - `CleaningCategory` in `PureMac/Models/Models.swift` defines these categories: System Junk, User Cache, AI Apps, Mail Files, Trash Bins, Large & Old Files, Purgeable Space, Xcode Junk, Brew Cache, Node Cache, Docker Cache, Universal Binaries, Language Files.
  - The scan paths for those categories are in `Services/ScanEngine.swift`.
  - `Logic/Utilities/ProviderPaths.swift` lists iCloud/FileProvider paths to protect.
  - `OrphanSafetyPolicy.swift` holds the safety rules for orphan detection.
  - App-uninstall matching uses `Logic/Scanning/Conditions.swift`: an `AppCondition` per app with bundleID, includeTerms, excludeTerms and force include/exclude paths, 28 entries. It also uses `Locations.swift`, which lists the Library search roots.
- **Coverage:** caches, logs, app leftovers, Xcode, Homebrew, npm, Docker, mail, trash, language files, universal binaries, and AI-app caches (e.g. Ollama).
- **Maintenance:** very active (HEAD 2026-11-06).
- **Provenance note:** `Conditions.swift` and `Locations.swift` match Pearcleaner's files of the same name in structure and in much of their data:
  - Both have a per-app include/exclude/force-path struct.
  - Both have a `standardLibrarySubdirectories` set.
  - The Xcode rule has the same terms: `["com.apple.dt", "xcode", "simulator"]`, excluding Xcodes, `com.oneminutegames.xcodecleaner`, and so on.
  - The entry counts are 28 vs 29.

  PureMac's README mentions Pearcleaner only in a feature comparison table. Treat those two files as possibly derived from Pearcleaner's Commons-Clause code, and learn from them instead of copying them. The rest of PureMac, such as the category paths and safety policy, looks independently written.

### 2. ClearDisk (MIT): developer-cache catalog with risk levels
- **License:** `MIT License, Copyright (c) 2026 Kadir Can Ozden`.
- **Rules:**
  - `DiskMonitor.allCachePaths()` returns about 61 `(name, SF Symbol icon, path, riskLevel "safe"/"caution"/"risky", group)` entries. Examples are Xcode DerivedData (safe), Archives (caution), CoreSimulator Devices (caution), iOS DeviceSupport, Previews, SwiftPM, CocoaPods, Carthage, Homebrew, npm, pip, Cargo, Go and Gradle.
  - `cacheDescriptions` gives a plain-English line per entry, e.g. "Rebuilds automatically…".
  - `AppCacheCatalog.swift` adds app caches with `CacheSafetyDetails(removes:, keeps:, note:)`. It also finds Sparkle and Squirrel `ShipIt` update payloads dynamically.
- **Coverage:** developer caches are strong. There are some app/browser caches and no uninstaller.
- **Why it matters:** the risk level and the "removes / keeps" explanations are a ready-made UX model for a review-before-delete SwiftUI app.

### 3. mac-cleanup-py (Apache-2.0)
- **License:** Apache License 2.0 (LICENSE; `license = "Apache-2.0"` in `pyproject.toml`). There is no NOTICE file in the repo.
- **Rules:** `mac_cleanup/default_modules.py` has 43 modules, each a function that adds glob `Path`s and/or shell `Command`s, about 105 `Path(...)` calls. The modules include trash, system_caches, system_log, jetbrains, adobe, chrome, ios_apps, ios_backups, xcode, xcode_simulators, dropbox, google_drive, composer, steam, minecraft, android, gradle, brew, gem, docker, pyenv, npm, pnpm, yarn, bun, pod, go, teams, poetry, java_cache, dns_cache, telegram, nuget, obsidian, chromium, arc and others. `module_template.py` shows how to write a module.
- **Coverage:** wide but blunt.
- **Caution:** some defaults are destructive:
  - `ios_backups` removes `~/Library/Application Support/MobileSync/Backup/*`.
  - `system_caches` removes all of `~/Library/Caches/*`, behind a prompt.
  - It runs `xcrun simctl erase all`.
  
  Reuse the path list, but put every entry behind TidyMyMac's own risk classification.
- **Maintenance:** active (2026-10-26).

### 4. Pearcleaner (Apache 2.0 + Commons Clause): best uninstall-leftover heuristics
- **License (exact):** LICENSE.md opens with the "Commons Clause" License Condition v1.0 and then the Apache License 2.0 text. It states "License: Apache 2.0 with Commons Clause".
  - The clause removes the right to "Sell" the software.
  - It also requires that "any license notice or attribution required by the License must also include this Commons Clause License Condition notice".
  - The README calls it "source-available and fair-code licensed".
- **Rules:**
  - `Locations.swift` lists app search roots, about 76 `$HOME` paths plus `/Library` roots. Plugin categories cover Audio (VST/VST3/AU/CLAP/HAL), PreferencePanes, QuickLook, Screen Savers, Internet Plug-Ins, CoreImage, ColorPickers and Fonts.
  - `Conditions.swift` holds 29 per-app `Condition` rules: bundle_id, include, exclude, includeForce, excludeForce. These cover Xcode/Xcodes, VS Code vs Insiders, Native Instruments and others.
  - It also has `skipConditions` for system prefixes to never touch, a large `skipDeepSearch` set of Library subfolders, and a `skipReverse` token list for orphan detection.
- **Coverage:** app leftovers, orphaned files, plugins, Homebrew, PKG receipts, and launch agents/daemons. It is not a cache/junk cleaner.
- **Maintenance:** README says "Project Status: On Hold… development on the app has basically stopped since end of 2025". The last commit was 2026-06-22.
- **Verdict:** learn from the approach (the `Condition` model and the skip lists). TidyMyMac is personal and free, so copying is permitted by the license text. It is not plain Apache, though, so under our policy treat it as learn-only unless the owner explicitly accepts the Commons Clause.

### 5. Mole (GPL-3.0)
- **License:** GNU GPL v3 (LICENSE). The README says "Any modified version you share must remain under the same license… credit Mole as the upstream source".
- **Rules:**
  - Bash modules in `lib/clean/`: `user.sh` has about 183 `safe_clean`-style calls (browsers such as Chrome GPU/shader/code caches, Firefox, Messages caches, Dropbox, recent items). `app_caches.sh` has about 151 and `dev.sh` about 126 (Xcode DerivedData, DocumentationCache, simulators, many toolchains).
  - The other modules in `lib/clean/` are `system.sh`, `caches.sh`, `brew.sh`, `project.sh`, `snapshots.sh` and `purge_shared.sh`.
  - Uninstall uses `find_app_files` / `find_app_system_files` in `lib/core/app_protection.sh`.
  - `lib/core/app_protection_data.sh` is a data-only list of protected bundle IDs and patterns (`SYSTEM_CRITICAL_BUNDLES` and others).
- **Coverage:** the broadest of all candidates (caches, logs, browsers, dev tools, Xcode, app leftovers, Homebrew, Steam, purge of project artifacts, Time Machine snapshots). It is also the most safety-hardened: process-running guards, whitelist, and symlink resolution.
- **Maintenance:** extremely active (commit on 2026-11-07).
- **Verdict:** best reference for which paths are safe and which guards are needed. Do not copy code or path lists; re-derive them.

### 6–7. BleachBit + CleanerML (GPL-3.0)
- **License:** the README states "BleachBit itself, including source code and cleaner definitions, is licensed under the GNU General Public License version 3… or any later version". The XML files carry `SPDX-License-Identifier: GPL-3.0-or-later`. The `cleanerml` community repo has a GPL-3.0 COPYING file.
- **Format:** CleanerML XML. A `<cleaner>` contains `<running>` (process guard), `<var>` with per-OS `<value os="macos">`, and `<option>` blocks of `<action>`. It is schema-validated by `doc/cleaner_markup_language.xsd`. `os="darwin"` is a deprecated alias for `macos` (`bleachbit/General.py`).
- **macOS coverage:** weak.
  - Only 19 of 110 `cleaners/*.xml` contain `os="macos"` paths: adobe_reader, android_studio, brave, docker, firefox, gimp, google_chrome, google_earth, helium, libreoffice, safari, teamviewer, vivaldi, vlc, vscode, waterfox, zen, zoom, zsh.
  - Many others use `os="unix"`, which matches macOS but points to Linux-style paths (`~/.cache`, `~/.config`).
  - The README does not say macOS is supported.
- **Verdict:** a good model for a declarative rule format (process guard, per-OS variables, options). Learn the schema idea only.

### 8. sunknudsen app-cleaner.sh (MIT)
- 122-line script. It is the original inspiration for Pearcleaner, according to Pearcleaner's README.
- It holds a clean list of about 27 locations where apps leave files: `~/Library/{Application Scripts, Application Support, Containers, Caches, HTTPStorages, Group Containers, LaunchAgents, Logs, Preferences, Preferences/ByHost, Saved Application State, WebKit…}` and the `/Library` equivalents. It also checks `/private/var/db/receipts/*.bom`.
- Matching is a simple `find -iname "*<app name>*"` / `"*<bundle id>*"` at maxdepth 1.
- The MIT license makes it the cleanest seed list for uninstall locations.

### 9. Kondo (MIT)
- `kondo-lib/src/lib.rs` maps project marker files (Cargo.toml, package.json, Package.swift, Podfile, build.gradle, pubspec.yaml, …) to build-artifact directories (`target`, `node_modules`, `.build`, `build`, `.gradle`, …). It has about 30 project types.
- Useful if TidyMyMac adds a "project build artifacts" cleaner.

### 10–11. fwartner/mac-cleanup and Clean-Me (MIT, stale)
- Small, outdated path lists (Xcode DerivedData/Archives/Device Logs, `~/Library/Caches`, logs, Mail Downloads, ASL logs). They are superseded by mac-cleanup-py and PureMac.
- Clean-Me's `Paths.swift` includes risky targets such as `~/Downloads/`, `/.Spotlight-V100/` and `/.DocumentRevisions-V100/`. Do not copy those.

---

## Ranked recommendation

1. **ClearDisk (MIT): copy with credit.** It is Swift, risk-classified (`safe`/`caution`/`risky`) and has user-facing "removes / keeps" text. It is the best starting point for TidyMyMac's cache and developer-junk rule table.
2. **mac-cleanup-py (Apache-2.0): copy with credit.** It has the widest permissively licensed path list (43 modules). Pull paths from it, but reclassify the destructive ones (iOS backups, all of `~/Library/Caches`, `simctl erase all`).
3. **sunknudsen app-cleaner.sh (MIT): copy with credit.** It is the cleanest permissively licensed seed for the uninstaller's leftover-location list and its name/bundle-ID matching.
4. **PureMac (MIT): copy with credit for categories, scan paths and safety policy only.** It is the closest SwiftUI architecture. Do not copy its `Conditions.swift` / `Locations.swift` because they appear to come from Pearcleaner.
5. **Mole (GPL-3.0): learn only.** It is the most comprehensive and most actively maintained reference. Use it to check coverage and safety guards (process-running checks, protected bundle IDs, symlink handling), but write TidyMyMac's own rules.
6. **Pearcleaner (Apache 2.0 + Commons Clause): learn only (policy).** It is the best per-app uninstall heuristics, through the include/exclude/force-path `Condition` model and its skip lists. Copying needs an explicit decision to accept the Commons Clause. It is also on hold.
7. **Kondo (MIT):** reuse later for a project-artifacts feature.
8. **BleachBit / CleanerML (GPL-3.0): learn only**, mainly for the declarative XML rule-schema design. Its macOS path coverage is thin.
9. fwartner/mac-cleanup and Clean-Me: skip, as they are stale and superseded.

**Suggested approach:** define TidyMyMac's own declarative rule schema in JSON or Swift, borrowing ideas from CleanerML and Pearcleaner's `Condition`. Each rule should carry id, label, paths/globs, a running-process guard, risk level, and removes/keeps text. Seed the rules from ClearDisk, mac-cleanup-py, app-cleaner.sh and PureMac, with an attribution file listing each source and license. Check the result against Mole for gaps and missing guards.

---

## Sources
- PureMac: https://github.com/momenbasel/PureMac — `LICENSE`, `PureMac/Models/Models.swift`, `PureMac/Services/ScanEngine.swift`, `PureMac/Logic/Scanning/Conditions.swift`, `PureMac/Logic/Scanning/Locations.swift`, `PureMac/Logic/Utilities/ProviderPaths.swift`, `README.md` (comparison table)
- ClearDisk: https://github.com/bysiber/cleardisk — `LICENSE`, `README.md`, `Sources/ClearDisk/DiskMonitor.swift`, `Sources/ClearDisk/AppCacheCatalog.swift`
- mac-cleanup-py: https://github.com/mac-cleanup/mac-cleanup-py — `LICENSE`, `pyproject.toml`, `mac_cleanup/default_modules.py`, `module_template.py`
- Pearcleaner: https://github.com/alienator88/Pearcleaner — `LICENSE.md`, `README.md` (status + license section), `Pearcleaner/Logic/Conditions.swift`, `Pearcleaner/Logic/Locations.swift`
- Mole: https://github.com/tw93/Mole — `LICENSE`, `README.md` (License section), `lib/clean/*.sh`, `lib/core/app_protection.sh`, `lib/core/app_protection_data.sh`
- BleachBit: https://github.com/bleachbit/bleachbit — `COPYING`, `README.md` (Licenses), `cleaners/*.xml`, `doc/cleaner_markup_language.xsd`, `bleachbit/General.py`
- CleanerML: https://github.com/bleachbit/cleanerml — `COPYING`
- Sun Knudsen app-cleaner: https://github.com/sunknudsen/privacy-guides/tree/main/archive/how-to-clean-uninstall-macos-apps-using-appcleaner-open-source-alternative — `app-cleaner.sh`; repo `LICENSE`
- Kondo: https://github.com/tbillington/kondo — `LICENSE`, `kondo-lib/src/lib.rs`
- fwartner/mac-cleanup: https://github.com/fwartner/mac-cleanup — `LICENSE`, `mac-cleanup`, `README.md`
- Clean-Me: https://github.com/Kevin-De-Koninck/Clean-Me — `LICENSE`, `Clean Me/Paths.swift`
- Commons Clause: https://commonsclause.com/ (linked from Pearcleaner README)
