# Release checklist

The release gate from [spec 017 §6](spec/017-test-plan.md#6-release-gate). Copy this file's checklist into the release commit filled in, then tag `vX.Y` on that commit. A failure in steps 5 to 7 blocks the release; there is no override.

| | |
|---|---|
| Version | 1.0 (build ___) |
| Commit | `________` |
| Date | ____-__-__ |
| Checked by | John |
| Form | ☐ Short (steps 1–4) ☐ Full (steps 1–8) |

**Full form** is required when any of `Packages/TidyCore/Sources/SafetyFloor`, `HelperCore`, `Helper/`, `RuleEngine` or `Rules/` changed since the last release:

```bash
git diff --stat v<last>..HEAD -- Packages/TidyCore/Sources/SafetyFloor Packages/TidyCore/Sources/HelperCore Helper Packages/TidyCore/Sources/RuleEngine Rules
```

For v1.0 there is no previous release, so the full form applies.

## Short form (always)

### 1. CI green on the merge commit
- [ ] The `CI` workflow passed on the merge commit on `main`.

### 2. `scripts/check-local.sh` green
- [ ] All package tests, rule lint and safety lint pass.
- [ ] Signed Release build; `codesign --verify --deep --strict` passes.
- [ ] Hardened runtime on; team `26TUUFN7M2`; not ad hoc.
- [ ] Helper plist label and `BundleProgram` correct.

### 3. Manual click-through (signed build in `/Applications`)
- [ ] First-run sheet: both steps, Later and Get Started.
- [ ] Each sidebar module opens: Tidy Up, Health, Cleanup, Declutter, Disk Map, Applications, Performance, Protection, My Tools.
- [ ] My Tools: every tile opens the module and tab it names; search filters the grid.
- [ ] Tidy Up dry run on John's account (Cleanup › Dry Run, or Review then a dry run); the list looks right. No real clean.
- [ ] Menu bar popover: four monitors update, alert switches, Open TidyMyMac, Run Tidy Up.
- [ ] Settings (⌘,): every pane opens and saves.
- [ ] Keyboard: ⌘R scans in every module that scans; Space quick-looks a highlighted row; ⌘⌫ ticks highlighted rows and removes nothing; ⌘↑ goes up in Disk Map; Esc and Return work in sheets and alerts.

### 3a. Accessibility pass (style guide §8)
- [ ] VoiceOver (⌘F5): the sidebar, a Cleanup category and its item rows, the review sheet, a confirm alert, the Disk Map list and a My Tools tile all read with names, not "button" or "checkbox" alone. Toasts are read out.
- [ ] Tick boxes read what they tick ("Select …", "Tick all in …"), and the lock badge reads "Needs your administrator password".
- [ ] Reduce Motion on (System Settings › Accessibility › Display): the scan ring and toasts don't animate.
- [ ] Increase Contrast on, in light and in dark: risk badges, destinations and status dots stay readable, each with a word or symbol, never colour alone.
- [ ] Full Keyboard Access on: every button in the footer bars and sheets can be reached with Tab.

### 4. Install over the previous build
- [ ] The helper restarts silently (spec 005 §4.3); no new approval prompt.
- [ ] Run history is still there.

## Full form (adds)

### 5. Throwaway-account real run (spec 017 §5)
- [ ] `scripts/seed-tidytest.sh` run as `tidytest`.
- [ ] Tidy Up with defaults, Uninstaller on the dummy app, Trash bins.
- [ ] `scripts/verify-tidytest.sh`: all PASS.
- [ ] Note whether the helper answered `tidytest`: ____

### 6. Real-helper canary run (spec 017 §4.3)
- [ ] `sudo scripts/canary.sh setup` created the canaries.
- [ ] Only the ticked canaries were removed; `sudo scripts/canary.sh check` reports every other canary and zone listing unchanged.

### 7. Experimental rules
- [ ] Dry run of every `experimental` rule on John's account; John reviewed the list.
- [ ] Rules that look right are `verified` in the same PR (spec 006 §6).

### 8. Live update check
- [ ] Applications › Updates against 5 installed apps matches what each app's own "Check for Updates" says.

| App | TidyMyMac says | App says | Match |
|---|---|---|---|
| | | | |
| | | | |
| | | | |
| | | | |
| | | | |

## Sign-off

- [ ] All steps above pass.
- [ ] Tag: `git tag -a vX.Y -m "TidyMyMac X.Y"` and `git push origin vX.Y`.

Notes:
