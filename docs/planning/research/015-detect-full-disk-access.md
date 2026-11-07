# 015: Detecting a missing Full Disk Access grant reliably

Ticket: [015](../tickets/015-detect-full-disk-access.md). Researched 2026-11-07 for TidyMyMac (native Swift, macOS 14+, Apple Silicon, distributed outside the App Store, non-sandboxed, SMAppService admin helper).
Builds on [004](004-feature-privilege-needs.md), [008 results](008-mac-checks-results.md) and [spike 009 results](../spike-009/RESULTS.md).

## TL;DR

1. **There is no API to check or request Full Disk Access (FDA), and no supported probe path.** Apple DTS said so in 2019 [S1] and again in August 2026 for macOS 27: "The answer to all three of these questions remains 'no'" [S2]. Every app guesses by trying to read protected data. Apple suggests a preflight: try the locations you actually need and warn the user if that fails [S2].
2. **Probe by actually opening or listing the item, never with `access()`, `isReadableFile`, `fileExists` or `stat`.** Those calls don't go through the TCC check, so the answer is wrong and the app doesn't get added to the FDA list [S3]. `stat` on `~/.Trash` succeeds without FDA, but listing it fails [008].
3. **Do not use TCC.db as the probe.** Its location is "not considered API" [S1][S3]. On macOS 27 the user TCC.db moved into a protected container, and an app that probed it got "denied" even with FDA granted [S2][S4].
4. **Recommended probe set:** list `~/.Trash`, `~/Library/Safari` and `~/Library/Mail`. Use three outcomes: any listing succeeds → granted; every existing path fails with `EPERM` → missing; nothing to test → unknown. This is Mole's three-outcome logic [S7] applied to `~/.Trash`, which tested as FDA-gated and present on John's Mac [008]. Skip `~/Library/Containers/*`: since macOS 14, reading another app's container can show a separate "access data from other apps" prompt [S9].
5. **Live detection without relaunch:** check again when the app becomes active, and every 1 s while the FDA onboarding screen is showing. That is what PureMac does [S6], and what an Apple security engineer advised in June 2026: "re-check permissions when it is foreground" [S5]. System Settings may offer "Quit & Reopen" [S10]. The app should not depend on that, but it needs a one-minute check on John's Mac (see Open questions).
6. **Deep link:** `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` is the link that shipping apps use (Pearcleaner [S8], PureMac [S6]). For macOS 13 and later, the newer form is `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles` [S11]. Neither is supported API [S12]. Open the first and fall back to the general Privacy & Security pane. Also offer "Reveal TidyMyMac in Finder" so the user can drag the app into the list [S6].
7. **Helper:** the SMAppService helper **inherits the app's FDA**. Spike 009 showed this on macOS 26.7.1, with no separate entry needed [009]. It matches Quinn's 2018 rule that a helper inside an approved app is covered automatically [S13]. The helper inherits a denial just as it inherits a grant: being root does not get around TCC [S14].

## 1. Is there an API? (No.)

- Quinn (Apple DTS, 2019) on probing TCC.db: "I recommend against the approach you're using because the location and permissions of the TCC database is not considered API. A better option is to do what you're really trying to do and then handle errors accordingly." [S1]
- Quinn, same thread: the scope of FDA "is likely to change over time", and Data Vaults exist "where requesting FDA won't help". Being root doesn't open a Data Vault, and neither does FDA. [S1]
- Kevin Elliott (Apple DTS, Aug 2026, about macOS 27), answering "is there an API / a supported method / a path to probe": "The answer to all three of these questions remains 'no'… there isn't currently a 'general' solution." His advice for a backup app: "create a list of data locations you know to be critical… and spot-check those locations… tell them that FDA *might* be the issue." He also says to run the preflight the same way as the real work, for example "go through your privileged helper (not your main app)". [S2]
- Apple security engineer (June 2026, on TCC.db being restricted): use the per-framework APIs where they exist, "re-check permissions when it is foreground and be prepared to handle unexpected states gracefully." FDA has no such framework API. [S5]

## 2. Which path to probe

### Rules for a correct probe
- **Use a real open or read.** Quinn on macOS 14.5: "you're calling `isReadableFile(atPath:)`, which calls `access`, which doesn't trip the TCC check. You have to actually try opening the file." A real open also "causes the app to show up in System Settings > Privacy & Security > Full Disk Access". [S3] Since Catalina, an app denied for lack of FDA is listed in that pane with its switch off (WWDC19, per [S3]). The failed probe is therefore also what puts TidyMyMac in the list, so the user doesn't need the "+" button.
- `stat` and `fileExists` are metadata calls that succeed without FDA: `ls -ld ~/.Trash` worked while `ls -A ~/.Trash` failed [008]. Mole's code comment says the same: "stat succeeds without FDA; only reading the contents proves access" [S7].
- **Read the error.** A TCC denial shows up as POSIX `EPERM` (1, "Operation not permitted"). In Foundation it is `NSCocoaErrorDomain` 257 (`NSFileReadNoPermissionError`) with an underlying `EPERM`, as in spike 009 [009] and the 008 shell output. `EACCES` (13) is ordinary Unix permissions and not a TCC result. A missing path (`ENOENT`) means the probe couldn't test anything.
- **Expect false negatives from other layers.** Data Vaults, SIP, Endpoint Security products and macOS 27's Application Support protection can deny access even with FDA granted [S1][S2][S4]. So treat "missing" as "probably missing" in the wording.

### Candidates

| Probe | Gated by FDA? | Always exists? | Notes |
|---|---|---|---|
| `~/.Trash` (list contents) | Yes. Listing fails with EPERM without FDA on macOS 26.7.1, no prompt [008] | Yes, created by Finder per user | Tested on John's Mac. TidyMyMac's Trash feature needs this exact read, which follows Apple's advice to probe what you use [S2]. Not used by Pearcleaner, PureMac or Mole |
| `~/Library/Safari` (list) | Yes, FDA-protected since 10.14 (Pearcleaner fallback [S8]; 004) | Almost always, even if Safari was never opened | Used by Pearcleaner [S8]. Mole uses `~/Library/Safari/LocalStorage` [S7] |
| `~/Library/Safari/Bookmarks.plist` / `CloudTabs.db` (open) | Yes | No, depends on Safari use and iCloud | PureMac probes files under Safari [S6]. A missing file only means the probe couldn't test anything |
| `~/Library/Mail` (list) | Yes | Only if Mail was ever set up | Pearcleaner, PureMac and Mole all include it [S6][S7][S8] |
| `/Library/Application Support/com.apple.TCC/TCC.db` (open) | Yes on 14 to 26 [S3]; spike 009 also showed the folder denied without FDA [009] | Yes | Apple says this location is not API [S1][S3]. On macOS 27 the user TCC.db moved and that probe returned false negatives [S2][S4]. The system copy reportedly stayed in place [S4]. Use it as a tie-breaker at most |
| `~/Library/Containers/com.apple.stocks` (list) | Yes (Pearcleaner's primary [S8]) | Usually | From macOS 14, reading another developer's container can show a separate "would like to access data from other apps" prompt; FDA apps are exempt [S9]. Avoid, so a probe never causes a prompt |
| `~/Library/Messages` | Yes [S7] | If Messages was used | Personal data; reading it, even only to probe, looks bad in a privacy review. Skip |

**Pearcleaner caveat:** Pearcleaner's first check per path is `access(path, R_OK)`, and its debug report uses `isReadableFile` on TCC.db [S8]. According to [S3], `access` never goes through the TCC check, so that shortcut can report "granted" without FDA (unless Unix permissions deny the read). Don't copy it.

### Sketch (Swift, for the spec)
```swift
enum FDAState { case granted, missing, unknown }

func probeFullDiskAccess() -> FDAState {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let probes = ["\(home)/.Trash", "\(home)/Library/Safari", "\(home)/Library/Mail"]
    var tested = 0
    for p in probes {
        guard let dir = opendir(p) else {           // real open, goes through TCC
            if errno == EPERM { tested += 1 }       // TCC/SIP denial
            continue                                // ENOENT/EACCES: not evidence
        }
        closedir(dir)
        return .granted                             // any success means granted
    }
    return tested > 0 ? .missing : .unknown
}
```
`opendir` performs a real open (the TCC check happens at open time per [S3]). `FileManager.contentsOfDirectory` also works, but it reads the whole listing and reports errors less directly.

## 3. Detecting the grant without a relaunch

- **No Apple statement says a running process sees a new FDA grant immediately.** The newest Apple guidance is to re-check whenever the app comes to the foreground and to handle unexpected states [S5].
- **PureMac** checks FDA once per second while its onboarding permission page is open. It re-checks on `NSApplication.didBecomeActiveNotification` and on its main window and settings, and it says in the UI "We'll detect the change automatically" [S6]. **Pearcleaner** has a "Retry" button that runs the probe again in the same process [S8]. Both suggest that a grant reaches a running process, but neither proves it.
- System Settings may show **"Quit & Reopen"** after you turn on FDA. SpamSieve's manual says to click it "if applicable" on recent macOS and to relaunch only "if it's not already open" [S10]. TidyMyMac should save its state so a forced relaunch is harmless, and should still check live.
- Older developer reports (2018 to 2019) describe needing to toggle FDA and relaunch the app and its XPC helper when the code identity changed [S13][S1]. That is the development-time "TCC remembers an old signature" case. Use `tccutil reset SystemPolicyAllFiles <bundle-id>`, which runs without root [008], and PureMac offers it as a reset button [S6].
- **Helper:** in spike 009 the grant was followed by unregister and re-register before the helper was probed again [009]. Whether an already-running helper picks up a new grant without a restart is **untested**. The app restarts the helper after updates anyway (009 follow-up), so the safe design restarts it after a grant too (kickstart, or unregister and register).

## 4. System Settings deep link per version

| macOS | Link | Evidence |
|---|---|---|
| 14 Sonoma, 15 Sequoia, 26 Tahoe | `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` | Shipped in current Pearcleaner [S8] and PureMac (macOS 13+) [S6]. The legacy pane ID still redirects to the Privacy & Security extension |
| 13+ (newer form) | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles` | Used by the `permission-flow` Swift package, marked `@available(macOS 13.0, *)` [S11] |
| Fallback | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension` (pane without anchor) | Quinn's forum thread [S12] |

- Apple's position (Quinn, "Supported URL Schemes"): these links are undocumented, "Their use is unsupported… things might work, or they might not, and that state might change over time." The only documented macOS deep link nearby is `SMAppService.openSystemSettingsLoginItems()`, which TidyMyMac already uses for the helper [S12].
- Design: open with `NSWorkspace.shared.open`. If it returns `false`, open the anchor-free pane. Always show the text path "System Settings > Privacy & Security > Full Disk Access" as well. Neither Pearcleaner nor PureMac checks the OS version, because the same link has worked from 13 to 26 [S6][S8].
- PureMac also reveals the app in Finder so the user can drag it into the list when it hasn't appeared (it cites Homebrew installs without quarantine) [S6]. That matters for a self-built TidyMyMac in `~/Applications`.

## 5. Does the admin helper inherit FDA?

- **Yes, on macOS 26.7.1, for the SMAppService.daemon design.** Spike 009: before the grant the helper (uid 0) was denied (`EPERM`/257) on `/Library/Application Support/com.apple.TCC`. After adding only `TidySpike.app` to Full Disk Access it could read the folder, with no entry for the helper. FDA also survived a rebuild with the same signing identity [009]. The daemon plist used `BundleProgram` inside the app and `AssociatedBundleIdentifiers` naming the app.
- Apple background: Quinn (2018) described two expected cases. "Bundle your helper inside your app. In this case the helper will automatically be whitelisted because the parent app was whitelisted." A helper outside the bundle needs its own grant [S13]. Code identity has to be consistent: bundle ID, signing identifier, same team [S13].
- **Root alone is not enough:** without the grant the root helper was still denied [009]. That matches 002's note that a root process does not get FDA by itself [S14]. The osascript "with administrator privileges" fallback (plan C) was **not** tested for inheritance. Assume it lacks FDA.
- Apple DTS recommends running the preflight in the privileged helper when that is the process doing the work [S2]. TidyMyMac should run one probe in the app (it puts the app in the list and shows the UI state) and the same probe in the helper before any helper job that touches protected paths.

## 6. macOS 27 notes (outside the ticket's 14 to 26 range, but John will upgrade)

- The user TCC.db moved to a protected container under `/private/var/containers/Data/`. Probes against the old user path return a false "missing" [S2][S4].
- macOS 27 adds `com.apple.macl` protection to selected non-sandboxed apps' `~/Library/Application Support/<name>` folders (Firefox, for example), from a hard-coded list in `sandboxd`. FDA reportedly doesn't help [S4]. Cleaner rules that touch those folders will fail with `EPERM` even with FDA, so the error text must not blame FDA by default.

## Open questions (one-minute checks on John's Mac)
1. Live grant: run the probe in a loop in a test app with no FDA, turn FDA on in System Settings without quitting, and see whether the next probe flips to granted. Note whether "Quit & Reopen" appears. [S5][S6][S10]
2. Does `open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"` land on the Full Disk Access list on 26.7.1? Test the `PrivacySecurity.extension` form too.
3. Does a running helper see a new grant without kickstart? (Not covered by spike 009.)

## Recommendation

- **Probe:** a real `opendir` on `~/.Trash`, then `~/Library/Safari`, then `~/Library/Mail`. Any success means granted. Every existing path failing with `EPERM` means missing. No path to test means unknown, shown as "can't tell" with the Settings button still offered. Don't use `access`, `isReadableFile`, `stat` or TCC.db, and don't probe `~/Library/Containers`. Run the probe at launch (this also adds TidyMyMac to the FDA list), on every `didBecomeActive`, once per second while the FDA onboarding sheet is showing, and in the helper before any helper job that touches protected paths.
- **Grant flow:** an onboarding sheet with "Open Settings", which opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and falls back to `…com.apple.settings.PrivacySecurity.extension`. Add "Reveal in Finder" for drag-in and a typed path as a final fallback. When the probe flips, close the sheet and restart the helper. Never require a relaunch, but let the app cope with one.
- **Degrade gracefully:** features that need FDA (Trash bins, Mail, Safari privacy, containers, iOS backups; see 004) show "Needs Full Disk Access" with the same button and are never silently skipped. A per-item `EPERM` while the probe reports "granted" is shown as "protected by macOS", not as an FDA problem.
- **Helper:** grant only the app; the helper inherits (proven in 009). Add no separate helper entry and no TCC.db reads. Add a "Reset permission" button that runs `tccutil reset SystemPolicyAllFiles <bundle-id>` for stale-signature cases after re-signing.
- Run the three one-minute checks above during the 017 test plan.

## Sources
- [S1] Quinn (Apple DTS), "Reliable test for Full Disk Access?", Mar 2019: https://developer.apple.com/forums/thread/114452
- [S2] Kevin Elliott (Apple DTS), "Detecting Full Disk Access on macOS 27: TCC.db path no longer usable", Aug 2026: https://developer.apple.com/forums/thread/841091
- [S3] Quinn (Apple DTS), "App not appearing in Full Disk Access list" (tested on macOS 14.5; `access` does not trip TCC; TCC.db is an implementation detail; WWDC19 session 701 quote on pre-populated entries): https://developer.apple.com/forums/thread/757768
- [S4] Michael Tsai, "Golden Gate Application Support Protection", 2026-07-24 (summarises Wojciech Reguła's and commenters' macOS 27 findings; secondary, used only for the macOS 27 notes): https://mjtsai.com/blog/2026/07/24/golden-gate-application-support-protection/ and the macOS 27 CI report at https://origin-devforums.apple.com/forums/thread/834560
- [S5] Apple Security Engineer, "Restricted TCC.db access: permissions check in real time", Jun 2026: https://developer.apple.com/forums/thread/833806
- [S6] PureMac (MIT licence), `PureMac/Services/FullDiskAccessManager.swift`, `Services/PermissionCoordinator.swift`, `Views/OnboardingView.swift`, `Views/MainWindow.swift`, `Views/Settings/SettingsView.swift`: https://github.com/momenbasel/PureMac (read only)
- [S7] Mole (GPL-3.0; read only, no code copied), `has_full_disk_access()` in `lib/core/ui.sh`: https://github.com/tw93/Mole/blob/main/lib/core/ui.sh
- [S8] Pearcleaner (Apache 2.0 with Commons Clause; read only), `Pearcleaner/Views/Components/PermissionsSheetView.swift` (`attemptFDACheck`, `openSettingsForPermission`), `Pearcleaner/Logic/Utilities.swift`: https://github.com/alienator88/Pearcleaner
- [S9] WWDC23 session 10053, "What's new in privacy" (macOS Sonoma app-container protection; FDA apps exempt): https://developer.apple.com/videos/play/wwdc2023/10053/
- [S10] C-Command SpamSieve manual, "Granting Full Disk Access" ("Quit & Reopen if applicable"): https://c-command.com/spamsieve/help/granting-full-disk-acce
- [S11] `permission-flow` Swift sources, `SystemSettingsDestination.swift` (`com.apple.settings.PrivacySecurity.extension` + `Privacy_AllFiles`, macOS 13+): https://docs.rs/crate/permission-flow/latest/source/PermissionFlow/Sources/SystemSettingsKit/SystemSettingsDestination.swift
- [S12] Quinn (Apple DTS), "Supported URL Schemes": https://developer.apple.com/forums/thread/761314 ; "Command to open Privacy & Security page", Oct 2024: https://developer.apple.com/forums/thread/765705 ; "SystemPreferences URL Scheme": https://developer.apple.com/forums/thread/761193
- [S13] Quinn (Apple DTS), "The Rules for Full Disk Access", Aug to Dec 2018: https://developer.apple.com/forums/thread/107546
- [S14] Quinn (Apple DTS), "BSD Privilege Escalation on macOS" (via research 002): https://developer.apple.com/forums/thread/708765
- [008] [008-mac-checks-results.md](008-mac-checks-results.md), John's Mac, macOS 26.7.1
- [009] [spike-009/RESULTS.md](../spike-009/RESULTS.md), John's Mac, macOS 26.7.1

CleanMyMac and MacPaw's PermissionsKit were deliberately not consulted.
