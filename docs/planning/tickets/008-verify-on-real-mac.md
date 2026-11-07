---
id: 008
title: Check three permission questions on a real Mac
type: wayfinder:task
status: closed
assignee: claude-thread-008
blocked_by: []
---

## Question

Research couldn't confirm these from docs; try them on John's Mac (macOS 14+) and record results:
1. Does the App Management permission also cover deleting another developer's app from /Applications?
2. Does `tccutil reset <service> <bundle-id>` need root?
3. Does reading ~/.Trash need Full Disk Access?

## Resolution

Tested on John's Mac (macOS 26.7.1, Apple Silicon). Details: [research/008-mac-checks-results.md](../research/008-mac-checks-results.md).
1. **App Management:** it blocks writes inside another developer's app bundle, but moving the whole app to the Trash works without it. The Uninstaller doesn't need App Management for user-owned apps. Updaters and stripping would.
2. **tccutil:** `tccutil reset <service> <bundle-id>` runs without root for every service tried, including ScreenCapture, Accessibility and SystemPolicyAllFiles. Not yet shown that it removes an existing system-level grant.
3. **~/.Trash:** listing it or measuring its size needs Full Disk Access ("Operation not permitted", no prompt). Moving items into it does not.
