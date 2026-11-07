---
id: 015
title: How to detect missing Full Disk Access reliably
type: wayfinder:research
status: closed
assignee: claude-research
blocked_by: []
---

## Question

On macOS 14 through 26, what is the most reliable way for an app to detect it lacks Full Disk Access (which protected path to probe, e.g. ~/Library/Safari/Bookmarks.plist vs the TCC db vs ~/.Trash per ticket 008), how to detect the grant without a relaunch, which System Settings deep-link URL opens the FDA pane on each version, and whether the admin helper inherits FDA (ticket 009 says it does). Cite open-source apps that do this.

## Resolution

Findings: [research/015-detect-full-disk-access.md](../research/015-detect-full-disk-access.md).
No API exists. Probe with a real opendir on ~/.Trash, then ~/Library/Safari, then ~/Library/Mail: any success = granted; all existing paths EPERM = missing; none exist = "can't tell". Never use access()/stat or TCC.db; skip ~/Library/Containers. Re-check when the app becomes active and every second while the FDA screen is open; restart the helper after a grant. Deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, falling back to the PrivacySecurity extension link, then Reveal in Finder. Helper inherits the app's FDA; osascript fallback assumed not to. Three one-minute Mac checks handed to ticket 017.
