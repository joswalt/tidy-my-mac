# 002 — Running privileged (root) operations without a paid Apple Developer account

**Question.** On macOS 14+ (Apple Silicon), with no paid Apple Developer Program membership (at most a free Personal Team), what are the workable ways for a personal SwiftUI app to run root operations? What changes if we later pay $99/year? What should we do for a personal-use app that might later be distributed for free outside the App Store?

**Date researched:** 2026-11-07. Main sources: Apple documentation, Apple Developer Forums posts by Apple DTS engineers (Quinn "The Eskimo!", Kevin Elliott), Apple Support / Apple Developer News, and the sudo project. The few non-Apple sources are labelled as such.

---

## TL;DR

| Option | Works today without a paid account? | What the user sees | Main risk |
|---|---|---|---|
| `SMAppService.daemon` (macOS 13+) | **Probably yes, for local use.** Apple says to sign the app and helper with the same Apple-issued identity, and ad-hoc signing "will" cause problems. A Personal Team "Apple Development" identity is Apple-issued and stable. This is plausible but not confirmed by Apple. Community projects report that ad-hoc works, with churn after each rebuild. | A "Background Items Added" notification, then an admin approves in System Settings > General > Login Items. This happens once. | A root daemon that is always available. You must authenticate clients over XPC. |
| `SMJobBless` (deprecated in macOS 13) | **Effectively no.** It assumes Developer ID code-signing requirements. | Admin password dialog | Deprecated, and its signing requirements are fiddly |
| `AuthorizationExecuteWithPrivileges` (deprecated since 10.7) | Still in the SDK as a deprecated C function. It is not usable from Swift directly. One third-party report says it broke. | Admin password dialog each time | Apple: "will indiscriminately run any tool". There is no secure link between the caller and the code that runs. |
| `osascript` / `do shell script … with administrator privileges` | **Yes.** It needs no signing at all. | Admin password dialog each time (Touch ID is not offered to third-party clients) | Apple says it is "not as API" and that Apple would deprecate it if they could. Shell-injection risk. |
| sudoers `NOPASSWD` rule + helper | Yes, as a manual admin setup | None after a one-time manual setup | A writable helper, or wildcard arguments, give silent root to any process running as the user |
| Manually installed LaunchDaemon (`/Library/LaunchDaemons`) | **Yes.** launchd does not require an Apple signature. | One-time admin step (Terminal / `.pkg`), plus a Background Items notification | The same as SMAppService, plus you must manage file ownership and permissions yourself |

**Recommendation (details at the end):** use **`SMAppService.daemon` with a small XPC helper embedded in the app bundle**, signed with the **free Personal Team "Apple Development" identity** while it is personal-use. Keep a fallback of **`osascript … with administrator privileges` for rare one-shot operations** during bring-up. If we later distribute, buy the $99 membership and switch to **Developer ID + notarization**. The SMAppService architecture stays the same. Only the signing identity and the helper's client-validation requirement (the Team ID) change.

---

## Background facts that apply to every option

- **All code on Apple Silicon must be signed, at least ad hoc.** Quinn (DTS): "if you're on Apple silicon be aware that all code must be signed. In situations like this you typically find that your code was ad hoc signed by the linker." "'Sign to Run Locally' is Xcode parlance for ad hoc signing." [S10]
- **Stable signing identity matters.** Quinn: "there are a bunch of subsystem within macOS that behave weirdly if your code doesn't have a stable code signing identity". For SMAppService bring-up specifically: "I recommend Apple Development signing during the bring up." [S10][S9]
- **Gatekeeper mainly applies to quarantined code.** Quinn: "for something simple like an app, Gatekeeper typically only kicks in if the app is quarantined" (for example, a file downloaded by Safari). An app you build and run on your own Mac is not quarantined, so the lack of notarization does not matter for personal use. [S10]
- **macOS 15 Sequoia removed the Control-click Gatekeeper override.** Users "will no longer be able to Control-click to override Gatekeeper when opening software that isn't signed correctly or notarized. They'll need to visit System Settings > Privacy & Security". Anyone we send an un-notarized build to must take that extra step. [S11]
- **A free account cannot make Developer ID certificates or notarize.** Developer ID certificates (Application / Installer) require the Account Holder role in a program membership, and notarization is the Developer ID companion. A free account gets a Personal Team only. [S12][S13]
- **Apple's own overview of escalation options** is Quinn's "BSD Privilege Escalation on macOS" post [S1]. Its recommendations:
  - Never use a setuid-root executable.
  - `sudo`/`osascript`/`authopen` are "not appropriate to use as API".
  - For ad hoc distribution with one-shot privileges, AEWP or AppleScript is acceptable. For wide distribution, don't use AEWP.
  - If you need privileges only at install time, use an installer package.
  - For ongoing privileges without an installer, use `SMAppService` (or `SMJobBless` on old systems).
  - Don't run GUI code as root.

---

## 1. `SMAppService.daemon` (ServiceManagement, macOS 13+)

**How it works.** The app bundle contains a helper executable and a launchd plist at `Contents/Library/LaunchDaemons/<label>.plist`. The plist uses `BundleProgram` (a path relative to the bundle) and usually `MachServices` for XPC. The app calls `SMAppService.daemon(plistName:).register()`. Apple's docs say SMAppService daemons replace "installing property lists in `/Library/LaunchDaemons`". [S2][S3][S4]

**Does it actually work without a paid account?**
- Apple's stated requirement is about *consistency*, not about the paid program. Quinn: "you should be signing both your embedded helper and your app with the same Apple-issued code-signing identity. If, for example, you are using ad hoc signing (Sign to Run Locally in Xcode parlance) then you will see problems like this" (`register()` failing with `Operation not permitted`, or the item vanishing from Settings). [S5]
- Quinn on distribution: "Direct distribution, outside of the Mac App Store, requires Developer ID signing. `SMAppService` imposes no additional constraints." That is, SMAppService itself does not demand Developer ID. [S6]
- **Personal Team "Apple Development" signing** is an Apple-issued, stable identity, and it is what Quinn recommends for bring-up [S9]. In thread [S5], the original poster on a free profile asked directly whether that mattered, and Apple did not answer. **No Apple source confirms or rules out Personal Team for daemons. Treat it as likely-but-unverified and test it early.**
- **Ad hoc** (non-Apple, community evidence): an open-source app reports "launch daemon via `SMAppService.daemon`, ad-hoc signing works", verified on macOS 27. It also reports that "after rebuilding an ad-hoc build the helper can stop answering until [the app] is switched off and on in Login Items", and that "A Developer-ID-signed build would not have this churn." [S20] This matches Quinn's warning: approval is tied to the code signature, and every ad hoc build has a new cdhash.
- Restricted entitlements (those that need a provisioning profile) need an app-like wrapper for the daemon, and they are a separate concern. Most file and system operations need none. [S2]
- Sandboxing: if the app is sandboxed, the daemon must be too. A sandboxed app with a non-sandboxed daemon is blocked on macOS 14.2+. Start with both non-sandboxed. [S2][S8]

**Prompts.**
- Calling `register()` triggers a "Background Items Added" notification (Options > Allow). The daemon does not run "until an admin approves the LaunchDaemon in System Preferences". After approval, it is "bootstrap[ped] … on each subsequent boot". [S2][S3]
- Before approval, `register()` returns `kSMErrorLaunchDeniedByUser` (Operation not permitted, code 1), and `status` is `.requiresApproval`. Use `SMAppService.openSystemSettingsLoginItems()` to send the user to System Settings > General > Login Items & Extensions > "Allow in the Background". [S3][S4][S8]
- After that, there is no per-operation password prompt, unless the daemon itself asks for one via Authorization Services (recommended for destructive actions). [S1]
- Debugging and reset: `sfltool dumpbtm` and `sfltool resetbtm` (restart after reset). Inspect the job with `sudo launchctl list <label>`. [S2][S14]

**Gatekeeper / notarization.** None are needed for local use. If distributed un-notarized, recipients must use "Open Anyway" in Privacy & Security (Sequoia+) [S11]. Login Items may also label the item as from an unidentified developer. Apple engineers have seen display bugs here even with Developer ID [S7].

**Security.**
- The daemon is a permanently available root service. Kevin Elliott (DTS): installation integrity is "largely handled by SMAppService", because the daemon lives in the signed bundle and app bundle protection (macOS 13+) prevents tampering. At runtime you must still "us[e] XPC to validate the connection itself and the authorization system to confirm user intent". [S15]
- Validate the peer's code signature (bundle ID + Team ID requirement) on every connection, for example with `NSXPCConnection.setCodeSigningRequirement` (macOS 13+).
- Expose narrow, typed operations, never "run this shell command".
- Quinn's warning: client authorization is per main executable, so in-process plug-ins are indistinguishable from it. [S1]

**With $99.** Sign both with Developer ID Application, enable the hardened runtime, and notarize. Approval then survives updates without churn, and Gatekeeper accepts the app. The code is unchanged apart from the Team ID in the XPC client requirement. Note that updates can still occasionally confuse Background Task Management records [S7]. Also, a non-Apple open-source issue reports an "Operation not permitted" re-register failure after an auto-update [S21]. Handle `status` defensively and offer a "reinstall helper" button.

## 2. `SMJobBless` (legacy)

- **Status:** deprecated in macOS 13 in favour of SMAppService [S1]. Quinn in 2023: "`SMJobBless` should still work as well as it always has" [S16]. He also says he "*strongly* favour[s] `SMAppService`. The only reason not to use it is if your app has to deploy to older systems" [S6].
- **Signing:** "SMJobBless assumes you're using an Apple-issued Developer ID. If you don't have a Developer ID, you should get one before proceeding." `SMPrivilegedExecutables` (in the app) and `SMAuthorizedClients` (in the helper) are code-signing requirement strings anchored to `apple generic` with Team-ID OU checks [S17]. In theory you could write requirements matching an Apple Development cert, but an ad hoc signature has no certificate chain and cannot satisfy them (our inference from the requirement grammar). A certificate common-name change alone broke a shipping app [S16]. Quinn calls it a "code signing requirements rabbit hole" [S6].
- **Prompts:** an admin password dialog at install. The helper is copied to `/Library/PrivilegedHelperTools` and runs as root from then on.
- **Verdict:** don't use it on macOS 14+. It is more fragile than SMAppService and does not help the no-account case.

## 3. `AuthorizationExecuteWithPrivileges` (AEWP)

- **Status:** Apple's docs mark it deprecated (availability listed as 10.1–10.7): "Use a `launchd`-launched helper tool and/or the Service Management framework". [S18] It is not available to Swift directly (it is marked unavailable). Projects call it through `dlsym` or an Objective-C shim. One third-party report (JUCE forum, 2023) says it "appears to have stopped working at all" for them after Xcode 14.3 [S22]. This is not confirmed by Apple, so treat its reliability as unknown.
- **Prompts:** the standard admin authentication dialog on every use. The dialog names the calling app, and there is no Touch ID ("The code that displays the authentication alert only shows the Touch ID option for Apple clients" [S19]).
- **Signing:** none required, which is why it is tempting without an account.
- **Security:** Apple's docs: it "will indiscriminately run any tool or application, severely increasing the security risk." Quinn: "there's no secure link between the code asking to elevate privileges and the code that's run with elevated privileges" [S19]. Quinn allows it only for ad hoc distribution, one-shot use [S1].
- **With $99:** nothing changes. It remains deprecated.

## 4. `osascript` / `do shell script "…" with administrator privileges`

- **Works today:** yes. It needs no signing, entitlements, or account. Quinn's privilege-escalation post even includes an `NSAppleScript` example, while noting it "probably isn't" the right choice [S1].
- **Prompts:** an admin username/password dialog on every invocation. AppleScript caches the authorization for a short time within the same process. It has no Touch ID. When invoked via the `osascript` tool, the dialog can be attributed to "osascript" rather than to your app [S22]. If the script touches another app via Apple Events, an Automation (TCC) prompt may also appear.
- **Gatekeeper/notarization:** not affected beyond the app itself.
- **Security / policy:** Quinn: "I view the AppleScript facility as equivalent to `sudo`: It's intended to be used by system administrators, and not as API. If we could deprecate the AppleScript approach in the context of an app running an AppleScript, we would." [S19]
  - Risks: shell injection (always use `quoted form of` and never interpolate untrusted paths), and training users to type their password into frequent prompts.
  - Protected locations (SIP, TCC-protected folders) still fail even as root. A root process does not get Full Disk Access by inheritance, and TCC "won't show UI for a launchd daemon" [S1].
- **With $99:** nothing changes.

## 5. sudoers-based helper (`/etc/sudoers.d/…` + `NOPASSWD`)

- **Works today:** yes, as a manual admin configuration. The app runs `sudo -n /path/to/helper <args>` via `Process`. The `NOPASSWD` tag removes the prompt [S23].
- **Prompts:** none at runtime. There is a one-time Terminal session with `sudo visudo -f /etc/sudoers.d/<file>`, or an AppleScript/pkg to write it.
- **Signing:** none (sudo doesn't check code signatures).
- **Security (serious):**
  - sudo warns that "if the user has write access to the command itself … the user may be able to swap it out". The helper and every parent directory must therefore be root-owned. It must **not** live inside a user-writable app bundle in `~/Applications`, and it must not be inside the app bundle at all unless `/Applications` is admin-only.
  - "Wildcards in command line arguments should be used with care … Wildcards can match any character, including white space." [S23]
  - Any malware running as the user gets the same password-less root access to whatever the rule allows. There is no caller authentication, unlike XPC code-signing checks.
  - Quinn lists `sudo` as an admin tool "not appropriate to use as API" [S1].
- **Distribution:** unsuitable. It edits a system security policy file on users' machines.
- **With $99:** no improvement. Switch to SMAppService.

## 6. Manually installed LaunchDaemon (`/Library/LaunchDaemons` + binary in a root-owned location)

- **Works today:** yes. launchd does not require an Apple-issued signature. On Apple Silicon the binary only needs a valid (ad hoc is fine) signature [S10].
- **Requirements:**
  - The plist is in `/Library/LaunchDaemons`. Executables conventionally go in `/usr/local/libexec` or similar root-owned paths.
  - Files "must be owned by the root user" and "must not be group writable or world writable".
  - Use plist keys (`UserName`, `MachServices`, `Sockets`, …) rather than daemonizing. [S24]
  - Load with `sudo launchctl bootstrap system /Library/LaunchDaemons/<label>.plist`.
- **Prompts:** a one-time admin step (Terminal `sudo`, an osascript admin prompt from the app, or a `.pkg` installer). Since macOS 13, Background Task Management also surfaces such items in Login Items and posts a background-item notification [S14].
- **Security:**
  - The binary is outside the app bundle, so it does **not** get SMAppService's bundle-integrity guarantee [S15]. You must make sure the binary path is root-owned and unwritable, or any user process can replace your root daemon.
  - You must still authenticate XPC clients. Updating and uninstalling are your problem.
- **Distribution:** Quinn: "If you already have an installer package in play, there's no need for `SMJobBless`. The package can install a `launchd` daemon directly." An installer package is "*by far* the easiest solution" when privileges are needed at install time [S1][S19]. Signing a `.pkg` for Gatekeeper requires a Developer ID Installer certificate, which needs a paid account [S13].
- **With $99:** sign the pkg (Developer ID Installer) and the daemon, and notarize. This is still a valid but more manual alternative to SMAppService.

---

## Recommendation

For a personal-use SwiftUI app that may later be distributed for free outside the App Store:

1. **Architect around `SMAppService.daemon` + XPC now.** It is Apple's supported path on macOS 13+ (Quinn: "I *strongly* favour `SMAppService`") [S6], and it is the only option that carries over unchanged to a distributed, notarized product.
   - Put the helper in `Contents/MacOS/` with `BundleProgram`, and add `MachServices`.
   - Expose a minimal, typed XPC protocol (no arbitrary shell).
   - Validate the client's code-signing requirement on every connection.
   - Ask Authorization Services for user confirmation on destructive operations.
   - Keep both targets non-sandboxed at first. [S1][S2][S8][S15]
2. **Sign both targets with the free Personal Team "Apple Development" identity**, not "Sign to Run Locally". It is stable across rebuilds, which avoids the re-approval churn Apple and community projects describe with ad hoc signing [S5][S9][S20].
   - First milestone: prove that `register()` → approve in Login Items → XPC call as root (`getuid()==0`) works with Personal Team signing on our Mac. No Apple source confirms this combination.
   - If it fails, fall back to ad hoc signing and expect to toggle the item in Login Items after rebuilds.
   - Use `sfltool resetbtm` between experiments.
3. **Fallback / escape hatch:** for rare one-shot operations, or if step 2 is blocked, use `NSAppleScript` `do shell script … with administrator privileges` with strictly quoted arguments. Apple considers this acceptable only for ad hoc, one-shot use [S1]. Do not build the product on it.
4. **Avoid** SMJobBless (deprecated, and needs Developer ID), AEWP (deprecated, not usable from Swift directly, insecure), sudoers `NOPASSWD` (silent root for any same-user process), and a hand-installed daemon (no bundle-integrity protection, and manual lifecycle).
5. **When we decide to distribute, pay the $99** and do the following:
   - Switch signing to Developer ID Application with the hardened runtime.
   - Notarize and staple.
   - Pin the XPC client requirement to our Team ID.
   - Handle `.requiresApproval` and `.notFound` states and offer a "reinstall helper" action.

   Without it, every recipient on Sequoia+ must allow the app in System Settings > Privacy & Security [S11], and Login Items may show the daemon as from an unidentified developer.

---

## Open questions / unverified

- Whether a free **Personal Team** "Apple Development" certificate is fully accepted by `SMAppService.daemon` on macOS 14/15/26+. Apple has not confirmed this either way [S5]. We need a hands-on test.
- How long Personal Team Mac development certificates stay valid before Xcode reissues them. A reissued certificate may require re-approval in Login Items.
- Whether AEWP still functions on current macOS/SDKs. One third-party report says no [S22], and Apple sources say only "deprecated".

## Sources

Apple (primary):
- [S1] Quinn "The Eskimo!" (Apple DTS), *BSD Privilege Escalation on macOS*: https://developer.apple.com/forums/thread/708765
- [S2] Quinn (Apple DTS), *Getting Started with SMAppService*: https://developer.apple.com/forums/thread/802443
- [S3] Apple docs, `SMAppService.register()`: https://developer.apple.com/documentation/servicemanagement/smappservice/register()
- [S4] Apple docs, `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice
- [S5] Apple Forums, *SMAppService Sample Code seems broken* (Quinn on same Apple-issued identity, ad hoc problems): https://developer.apple.com/forums/thread/799910
- [S6] Apple Forums, *SMAppService.daemon as root* (Quinn: no extra constraints beyond Developer ID for distribution; prefer SMAppService): https://developer.apple.com/forums/thread/751439
- [S7] Apple Forums, *Privileged daemon appears as unsigned in Login Items*: https://developer.apple.com/forums/thread/757463
- [S8] Apple Forums, *How to authorize LaunchDaemons* (sandbox matrix, approval flow): https://developer.apple.com/forums/thread/761249
- [S9] Apple Forums, *SMAppService with root Helper* (Quinn: use Apple Development signing for bring-up): https://developer.apple.com/forums/thread/733046
- [S10] Apple Forums, *Gatekeeper and code signing* (Quinn: Apple silicon signing, quarantine, ad hoc): https://developer.apple.com/forums/thread/740680
- [S11] Apple Developer News, *Updates to runtime protection in macOS Sequoia*: https://developer.apple.com/news/?id=saqachfa
- [S12] Apple, *Developer account overview / compare memberships*: https://developer.apple.com/support/compare-memberships/
- [S13] Apple, *Developer ID certificates*: https://developer.apple.com/support/developer-id/
- [S14] Apple Support (Deployment), *Manage login items and background tasks on Mac*: https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web
- [S15] Apple Forums, *Privileged helper without SMJobBless* (Kevin Elliott & Quinn on SMAppService integrity, XPC validation): https://developer.apple.com/forums/thread/801222
- [S16] Apple Forums, *Migrating away from SMJobBless*: https://developer.apple.com/forums/thread/725811
- [S17] Apple sample code, *SMJobBless ReadMe*: https://developer.apple.com/library/mac/samplecode/SMJobBless/Listings/ReadMe_txt.html
- [S18] Apple docs, `AuthorizationExecuteWithPrivileges`: https://developer.apple.com/documentation/security/authorizationexecutewithprivileges
- [S19] Apple Forums, *Questions about privilege escalation on macOS* (Quinn on AEWP, AppleScript, Touch ID, pkg): https://developer.apple.com/forums/thread/701118
- [S24] Apple archive, *Creating Launch Daemons and Agents*: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatinglaunchdJobs.html

Non-Apple (lower trust, used only where labelled):
- [S20] openproxy PR #2 (ad hoc SMAppService daemon on macOS 27, rebuild churn): https://github.com/kyivcommit/openproxy/pull/2
- [S21] exelban/stats issue #3716 (SMAppService re-register EPERM after update): https://github.com/exelban/stats/issues/3716
- [S22] JUCE forum, *Elevated permissions in macOS…* (AEWP report, osascript prompt attribution): https://forum.juce.com/t/elevated-permissions-in-macos-or-so-we-thought-edited/55419
- [S23] sudo project, *sudoers manual*: https://www.sudo.ws/docs/man/sudoers.man/
