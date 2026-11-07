# Spec 015: Detecting and onboarding Full Disk Access

Ticket: [015](../planning/tickets/015-detect-full-disk-access.md). Findings and sources: [research/015](../planning/research/015-detect-full-disk-access.md). Written for ticket 018 from the research recommendation, which the map already records as decided. Code: probe in `Monitors` (spec 016 §3), sheet in `App/Setup`. Screen: first-run sheet (spec 007 §6).

## 1. The probe

There is no API. TidyMyMac tries a real directory read:

```swift
enum FDAState { case granted, missing, unknown }
// probes, in order: <Home>/.Trash, <Home>/Library/Safari, <Home>/Library/Mail
// opendir succeeds on any → .granted
// every path that exists fails with EPERM → .missing
// nothing testable (ENOENT/EACCES only) → .unknown
```

- Uses `opendir` (a real open, which goes through TCC). Never `access`, `isReadableFile`, `fileExists`, `stat`, or TCC.db. Never probes `~/Library/Containers`.
- Paths come from the injected `Home` value (spec 017 §2), so tests feed fake `opendir` results.
- `unknown` is shown as "Can't tell" with the same Settings button.

## 2. When it runs

- At launch (this also adds TidyMyMac to the FDA list in System Settings, switched off).
- On every `NSApplication.didBecomeActiveNotification`.
- Once per second while the setup sheet is open.
- In the helper, before any helper job that touches a zone needing FDA (none in v1 strictly need it, but the check is cheap and gives a clear error).

## 3. Grant flow (first-run sheet step 1)

1. **Open System Settings** opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. If `NSWorkspace.open` returns false, open `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`, then the anchor-free `…PrivacySecurity.extension`.
2. The sheet always also shows the text path "System Settings › Privacy & Security › Full Disk Access" and a **Reveal TidyMyMac in Finder** link, for dragging the app into the list.
3. When the probe flips to granted: tick step 1, enable step 2 (helper), and if the helper is running send `shutdown()` so launchd restarts it with the grant (spec 005 §4.3). Whether this restart is needed is checked at first build (spec 017 §7 item 4).
4. Never require a relaunch. App state (selected module, scan results) survives one in case System Settings offers "Quit & Reopen".

## 4. Without FDA

- Features and rules with `needsFullDiskAccess` show greyed out with "Needs Full Disk Access" and the same button; they are never half-run or silently skipped. v1 list: Trash bins and the Trash alert/Health line, `cache.user.containers`, iOS backups, leftovers in Containers and Group Containers.
- An `EPERM` on one item while the probe says granted is shown as "Protected by macOS", not as an FDA problem (Data Vaults, macOS 27 `macl` folders).

## 5. Reset

Settings › Helper has **Reset Full Disk Access entry**, which runs `/usr/bin/tccutil reset SystemPolicyAllFiles io.github.joswalt.TidyMyMac` (no root), for stale-signature cases during development, then reopens the setup sheet.
