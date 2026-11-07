# First-build checklist (spec 017 §7)

Fill in with the first build that includes the helper (milestone 3). Date, macOS version and build number first.

- Date: 2026-11-07
- macOS: 26.7.1
- TidyMyMac build: 1.0 (1), milestone 3 branch

## 1. Helper (005 §11)

| Check | Result |
|---|---|
| Install Helper → Login Items approval → Settings › Helper says "Helper ready" | Pass |
| Dry run of every zone: Cleanup › Scan shows System caches, System logs, Old system log archives, Broken system login items | |
| Canary run on systemCaches: `sudo /Users/Shared/TidyMyMacTest/canary.sh setup`, tick only the A canary, the canary log folder and the TidyTest Dummy agent, Clean, then `sudo …/canary.sh check` | Run 1: B was also ticked (a category tick), and the check caught it; the helper removed exactly the 4 items it was sent. Run 2 (16:08): exactly 3 items removed, B untouched, RESULT: PASS. Follow-ups: the confirm now names every admin-rights item; `canary.sh check` no longer reports Data Vault folders (root can't stat them) as gone. |
| Password dialog: shown once per run? Offers Touch ID? | Once per run; offers Touch ID (005 §11 known unknown: yes) |
| Restore the Dummy agent from Health › Run History (it went to your Trash) | Pass (restored through the helper) |
| Rebuild + reinstall: helper restarts silently (no new approval) | |

## 2. Full Disk Access live grant (015 Q1)

With the setup sheet open, turn Full Disk Access on without quitting. Does step 1 tick within about a second? Does System Settings offer "Quit & Reopen"?

Result: step 1 ticked by itself; System Settings also offered "Quit & Reopen" (not needed).

## 3. Deep links (015 Q2, 013)

Does **Open System Settings** land on the Full Disk Access list? (Which of the three links worked?)

Result: yes, the first link (`com.apple.preference.security?Privacy_AllFiles`) lands on the list on 26.7.1.

## 4. Helper sees a new grant without restart (015 Q3)

## 5. `softwareupdate -l` timing (013)

`time softwareupdate -l` (twice) and `time softwareupdate -l --no-scan`:

## 6. WWDR G3 intermediate present

`scripts/check-local.sh` prints no WWDR warning:

## 7. Second user

Does the helper answer when TidyMyMac runs in the `tidytest` account (it asks for an admin password there)?

## Not yet checked

Items 4–7 (helper sees a grant without restart, `softwareupdate -l` timing, WWDR warning, second user) are open; they change defaults only and are re-checked at the M4/M6 builds or the release gate.
