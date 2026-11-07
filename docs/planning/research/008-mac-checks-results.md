# Ticket 008: permission checks on John's Mac

Run 2026-11-07 with [008-mac-checks.sh](008-mac-checks.sh) on John's Mac: macOS 26.7.1 (25G241), arm64.
Test app: CodexBar (`com.steipete.codexbar`, Developer ID team Y5PE65HELJ, quarantine xattr present, owned by the user).
Terminal had no Full Disk Access and (per the setup) no App Management permission.

## Q3: does reading ~/.Trash need Full Disk Access?
**Yes for reading, no for writing.**
- `ls -ld ~/.Trash` works (stat on the folder itself).
- `ls -A ~/.Trash` and `du -sk ~/.Trash` fail with "Operation not permitted". No prompt appeared.
- `touch ~/.Trash/file` and `mv App.app ~/.Trash/` succeed.
Consequence: moving items to the Trash needs nothing, but the Trash-bins feature (show size and contents, empty selectively) needs FDA. Without FDA the app can still empty the Trash by asking Finder over Apple Events (Automation permission).

## Q2: does `tccutil reset <service> <bundle-id>` need root?
**No.** Without sudo, reset succeeded (exit 0) for Camera, Microphone, ScreenCapture, Accessibility, SystemPolicyAllFiles and All.
Caveat: CodexBar may have had no stored grants, so this proves the command runs unprivileged, not that it removed an existing row from the system TCC database.

## Q1: does App Management also cover deleting another developer's app?
**No. App Management blocks changes inside another developer's app, but not moving the whole app to the Trash.** The first run was in iTerm, which turned out to be exempt; see the follow-up below. App Management protection was not enforced in this run: even writing a file *inside* the bundle (`touch CodexBar.app/Contents/tidytest`) succeeded, and renaming and moving the whole app to the Trash also succeeded. So the run did not exercise the protection. Likely causes: the terminal app used has App Management or Developer Tools permission, or the terminal is not Apple's Terminal.

### Follow-up (same day)
Writing an empty file inside a Developer ID app (Alfred 5):
- Apple Terminal (no App Management): `Operation not permitted`. The protection is active.
- iTerm: allowed. iTerm has App Management or Developer Tools permission, so the first run was in an exempt terminal.
- Apple Terminal on CodexBar: writing inside the bundle failed (`inside=1`, so the app is protected), but `mv CodexBar.app ~/.Trash/` succeeded (`trash=0`).

Consequence: the Uninstaller can trash user-owned third-party apps without App Management. Anything that edits inside a bundle (updaters patching in place, language or binary stripping) needs App Management. Root-owned apps still need the admin helper.
