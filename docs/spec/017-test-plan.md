# Spec 017: Test plan

Ticket: [017](../planning/tickets/017-test-plan.md). **Status: decided. John accepted all recommended defaults, 2026-11-07.** Builds on spec [005](005-admin-helper.md) §11, spec [006](006-safety-rules.md) §5–6, spec [016](016-repo-layout.md) §3, research [013](../planning/research/013-app-update-checks.md) and [015](../planning/research/015-detect-full-disk-access.md).

The one property everything here protects: **a run removes exactly the items John selected, in the way the review screen promised (Trash or delete), and nothing else.**

---

## 1. Decisions (recommended defaults)

| # | Question | Recommended default | Why |
|---|---|---|---|
| D1 | Where do destructive tests run? | **Three layers:** (a) fixture folders in a temp dir for all automated tests; (b) a throwaway standard user account `tidytest` on John's Mac for full real runs; (c) John's own account only for **dry runs**, plus real runs he chooses himself after the gate passes. | Fixtures catch logic bugs cheaply. A real second account gives real `~/Library`, Trash, TCC and Spotlight with nothing to lose. |
| D2 | A VM too? | **No VM in v1.** Root zones are tested with canary files (§4.3) instead. Revisit if a helper bug ever touches a non-canary file. | Apple ID and Personal Team signing inside macOS guests add setup cost for little extra safety, since the helper can only act on its own handles inside 6 fixed zones. |
| D3 | CI? | **GitHub Actions on every pull request**, macOS runner, no signing: package tests, rule lint, safety lint, unsigned app build. Nothing signed, no secrets. | Catches regressions before John reviews a PR. Private-repo macOS minutes are limited (they count at a multiple of Linux minutes), so CI runs on PRs only, not on every push. |
| D4 | What runs only on John's Mac? | Anything needing signing, the helper, TCC/FDA, a real home folder or a human eye (§3 table). Packaged as `scripts/check-local.sh` plus a checklist. | These cannot run on a hosted runner. |
| D5 | UI tests? | **No XCUITest in v1.** View models are unit tested; screens are covered by a manual click-through in the release checklist. | UI tests need signing and Accessibility permission, and break often; the risk lives in the libraries, not the views. |
| D6 | Coverage target? | **No percentage.** Instead, named required cases (§4) must exist and pass; the safety lint fails the build if a required case file is missing. | A percentage rewards easy tests; the dangerous paths are known by name. |
| D7 | What blocks a release build? | The **release gate** in §6, run in full when SafetyFloor, HelperCore, Helper, RuleEngine or `Rules/` changed; otherwise the short form. | One clear list; the expensive helper checks only when helper-side code moved. |
| D8 | When to run the one-minute Mac checks (015 and 013)? | **At the first real build**, as part of the first-release checklist (§7). The three shell-only ones can be run sooner with [017-mac-checks.sh](../planning/research/017-mac-checks.sh) if John wants the numbers early. | The FDA live-grant and helper-sees-grant checks need the real app; the others are cheap but change no design decision, only defaults (the `softwareupdate` timeout). |
| D9 | Network in tests? | **None.** Appcast and Homebrew tests use local fixture files. A live check of a handful of installed apps is a manual release step. | Tests stay deterministic and offline. |

## 2. Guardrails for the test code itself

A test suite for a cleaner is itself a cleaner. So:

1. **One home abstraction.** All code reaches the user's folders through a `Home` value (root URL plus derived `Library`, `Trash`, `Caches`…) passed in, never through `NSHomeDirectory()`, `homeDirectoryForCurrentUser` or `FileManager.urls(for:in:)` directly. Only `App/` constructs the real `Home`.
2. **Safety lint** (`scripts/safety-lint.sh`, runs in CI and locally) fails if those APIs, a literal `"/Users/"`, `"~/"` or `"/Library/"` path, or `removeItem`/`unlink`/`trashItem` appear outside the allowed files (`SafetyFloor`, the remover in `RuleEngine`/`HelperCore`, and `App/` composition root).
3. **`TestHome`** creates a fresh fixture under `FileManager.default.temporaryDirectory` and **refuses to start** if its resolved path is not inside the temp dir, is `/`, or contains `/Users/<real user>/` outside `$TMPDIR`. Every destructive test uses it.
4. Tests never need root and never call the real helper; `HelperCore` takes zone roots as parameters (spec 005 §11).
5. The real remover in tests runs with an extra **test fence**: a process-wide allowed root that the remover checks before any unlink or move. Set only by `TestHome`; absent in the shipping app.

## 3. What runs where

| Suite | CI (every PR) | `check-local.sh` on John's Mac | Release gate |
|---|---|---|---|
| Unit tests, all TidyCore libraries | ✓ | ✓ | ✓ |
| Rule lint (spec 006 §6 step 1) + schema | ✓ | ✓ | ✓ |
| Rule fixture tests (006 §6 step 2) | ✓ | ✓ | ✓ |
| Safety lint (§2) | ✓ | ✓ | ✓ |
| Snapshot-diff end-to-end on fixtures (§4.1) | ✓ | ✓ | ✓ |
| In-process XPC contract test (§4.3) | ✓ | ✓ | ✓ |
| Unsigned app + helper build | ✓ | | |
| Signed build (Personal Team) + `codesign --verify` + entitlement check | | ✓ | ✓ |
| Real helper on the machine (§4.3 manual) | | | ✓ full gate |
| Throwaway-account real run (§5) | | | ✓ full gate |
| Dry run of experimental rules on John's account (006 §6 step 3) | | | ✓ when rules changed |
| Manual UI click-through (§6) | | | ✓ |

CI details: `runs-on` the newest macOS image whose Xcode has Swift 6.4; `swift test --package-path Packages/TidyCore`, `scripts/lint-rules.sh`, `scripts/safety-lint.sh`, `xcodegen && xcodebuild build CODE_SIGNING_ALLOWED=NO`. Triggers: `pull_request` and manual. Timeout 20 min. No secrets, no certificates.

## 4. Required test cases (by library)

### 4.1 The core property: snapshot-diff end-to-end

`EndToEndTests` (in a test target that links RuleEngine, AppInventory, DiskAnalysis, RunLog, SafetyFloor):

1. Build a **fixture home** from a manifest: realistic junk for every v1 rule (caches, logs, DerivedData, AI model folders, a broken LaunchAgent, a fake `.dmg` in Downloads), plus **tripwires**: files in every protected-floor folder (Documents, Desktop, Keychains, Mobile Documents, CloudStorage, Mail, a `.photoslibrary`, an item inside an `.app` bundle, TidyMyMac's own support folder), a symlink from a cache folder pointing into Documents, a hard link, an APFS clone, a `uchg`-flagged file, a file named `com.apple.something` in a leftover location.
2. Take a **manifest snapshot**: every path with inode, size, mtime and flags.
3. Scan, select (a fixed selection, plus "everything ticked by default"), run for real.
4. Snapshot again and assert: **removed set == selected set**, each removed item is either gone (delete rules) or present in the fixture Trash with the same inode (trash rules), every tripwire is byte-identical, and the run log has exactly one entry per removed item with the right rule id and action.
5. Repeat with a **mid-run change**: between scan and run, swap a selected folder for a symlink, replace a file with a new inode, start a guarded "app" (a fake running-app checker). Those items must be skipped and logged as skipped.

A seeded **random tree** variant (fixed seeds in CI, a longer run in `check-local.sh`) generates nested folders, symlinks and odd names (spaces, Unicode NFD/NFC, newlines, 255-byte names) and re-asserts the same property.

### 4.2 SafetyFloor and RuleEngine

- Every protected-floor path, its children, and case/Unicode variants (`~/documents`, NFD forms) are refused; `/usr/local` is allowed only where a rule says so.
- Path containment (006 §5.3): `..`, symlinked item, symlinked parent, firmlink, other-volume (a mounted temp disk image in `check-local.sh`; CI uses a fake volume id), item equal to the rule root.
- Linter negative cases: one bad rule file per lint rule must fail with the named error.
- Each rule: at least one must-match and one must-not-match fixture (006 §6), checked by the safety lint.
- Sizes use allocated size: clone and hard link count once.
- `protected.json` deny names equal `HelperCore`'s compiled list (005 §5.1).

### 4.3 Helper

- **HelperCore unit tests** (CI): all cases listed in spec 005 §11 (zone escape, symlink swaps, inode change, deny list, delete in a trash zone, expired handle, `uchg`, `fts` not crossing a mounted image), with zone roots in a temp dir.
- **Contract test** (CI): app-side client and `HelperCore` connected through `NSXPCListener.anonymous()` in one test process. Covers every operation's request/reply encoding, protocol-version mismatch handling, and that no operation accepts a path from the client.
- **Restore ledger**: trash then restore round trip; restore when the original parent is gone; restore when the Trash item was emptied (clear error, no crash).
- **Manual on the real helper** (full gate): spec 005 §11 list, with **canary files**: before the run, `sudo` creates `TidyCanary-<date>` items in `/Library/Caches`, `/Library/Logs` and a fake `io.github.joswalt.TidyTest.Dummy` LaunchAgent plist with a missing program. The run may only remove the canaries John ticks; a script (`sudo scripts/canary.sh check`) then checks that the ticked canaries are gone and the untouched canaries and a listing of each zone's other items are unchanged; any difference prints a `FAIL` line, ends with `RESULT: FAIL` and exits 1. Re-run setup right before the run so ordinary system churn in those zones isn't reported. Order: setup, cleanup, `check`, and only then restore the Dummy agent from TidyMyMac's history; `sudo scripts/canary.sh check-restored` then confirms it came back as the same file (same inode), owned `root:wheel`, mode 644.

### 4.4 Other libraries

- **AppInventory**: a dummy app `TidyTestDummy.app` (bundle id `io.github.joswalt.TidyTest.Dummy`, built by the test target) with leftovers in each `leftover-locations` root; uninstall must find exactly those; a suite app with `sharedWith` keeps shared files; Apple-signed apps are never offered. Update checker: fixture appcasts (Sparkle, Electron `latest-mac.yml`, malformed, `http://`, deltas, min-system filters) and the ported Sparkle comparator tests verbatim.
- **DiskAnalysis**: treemap sizes vs `du -k` on a fixture; duplicates per ticket 014's rules incl. clones and hard links; Large & Old age filters.
- **Monitors**: parsing of `host_statistics64`/interface counters from recorded samples; FDA probe logic with injected `opendir` results (`EPERM`, `ENOENT`, success) mapping to granted/missing/can't-tell (015).
- **SystemTasks**: operation ids map to the allow-list; no shell strings anywhere.
- **RunLog**: append-only, survives a crash mid-write (truncated last line ignored), never written inside the fixture's removable areas.

## 5. Throwaway-account real run (`tidytest`)

1. One-time: John creates a standard (not admin) user `tidytest` in System Settings › Users & Groups.
2. `scripts/seed-tidytest.sh` (run as `tidytest`) builds the same fixture manifest as §4.1 in the real home, records a snapshot, and installs the dummy app in `~/Applications`.
3. Log in as `tidytest`, open the release build, grant FDA, run Tidy Up with defaults, then Uninstaller on the dummy app, then Trash bins.
4. `scripts/verify-tidytest.sh` diffs against the snapshot and the run log, prints PASS/FAIL per item. Reset with the seed script for the next release.

Helper operations from `tidytest` need an admin password, which also tests that a standard user can't skip authentication. Whether a helper approved from John's account answers a second user is untested; the first full run records it, and if it doesn't, helper steps stay in §4.3 and the `tidytest` run covers user-level features only.

## 6. Release gate

A "release" is a signed build John installs in `/Applications`. Tag `vX.Y`, and commit the filled-in `docs/release-checklist.md` with it.

**Short form (always):**
1. CI green on the merge commit.
2. `scripts/check-local.sh` green (all tests, signed build, `codesign --verify --deep --strict`, hardened runtime on, helper plist label and `BundleProgram` correct).
3. Manual click-through: first-run sheet, each sidebar module opens, Tidy Up dry run on John's account, menu bar popover, Settings.
4. Install over the previous build; helper restarts silently (005 §4.3); run history still there.

**Full form (adds), when SafetyFloor, HelperCore, Helper, RuleEngine or `Rules/` changed:**
5. Throwaway-account real run (§5): all PASS.
6. Real-helper canary run (§4.3 manual).
7. Dry run of every `experimental` rule on John's account; John reviews the list; rules that look right become `verified` in the same PR (006 §6).
8. Live update check against 5 installed apps; results match what each app's own "Check for updates" says.

A failure in 5–7 blocks the release; there is no override.

## 7. First-build checklist (runs once, with the first real build)

From spec 005 §11 and research 015/013, recorded in `docs/planning/first-build-results.md`:

1. Helper: dry-run every zone; real run on `systemCaches` (canaries); trash and restore one item from `launchItems`; trash and restore a root-owned app from `rootApps`; rebuild and confirm silent restart; does the password dialog offer Touch ID?
2. **FDA live grant (015 Q1):** with the FDA sheet open, turn FDA on without quitting; the sheet must close within ~1 s. Note whether System Settings offers "Quit & Reopen".
3. **Deep links (015 Q2):** does `…com.apple.preference.security?Privacy_AllFiles` land on the Full Disk Access list on 26.7.1? Does the `PrivacySecurity.extension` form? Does `…com.apple.Software-Update-Settings.extension` open Software Update (013)?
4. **Helper sees a new grant without kickstart (015 Q3):** with the helper running and FDA off, run a helper probe (denied), grant FDA, probe again before and after the app's helper restart. If it flips without restart, the restart in 015's grant flow becomes optional.
5. **`softwareupdate -l` timing (013):** `time softwareupdate -l` twice and `time softwareupdate -l --no-scan`; confirm `/Library/Preferences/com.apple.SoftwareUpdate.plist` is readable without root. Set the app's timeout to 3× the slowest run, minimum 60 s (default 120 s until measured).
6. AppleWWDRCAG3 intermediate present in the keychain (spike 009 gotcha), checked by `check-local.sh`.

Checks 3 and 5 can be run any time with [research/017-mac-checks.sh](../planning/research/017-mac-checks.sh).

## 8. Files this adds to the repo layout (spec 016)

```
scripts/check-local.sh  safety-lint.sh  lint-rules.sh  seed-tidytest.sh  verify-tidytest.sh
.github/workflows/ci.yml
docs/release-checklist.md
Packages/TidyCore/Tests/EndToEndTests/  (+ Fixtures/ manifests, TestHome, TidyTestDummy)
```
