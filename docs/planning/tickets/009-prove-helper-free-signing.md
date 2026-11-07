---
id: 009
title: Prove the admin helper works with free signing
type: wayfinder:task
status: closed
assignee: claude-009
blocked_by: []
---

## Question

Build a throwaway spike on John's Mac: a minimal SwiftUI app + SMAppService.daemon helper, both signed with the free Personal Team identity. Can it register, get approved in Login Items, and run one root operation over XPC? Does approval survive a rebuild? Needs John's OK before any code is written, and Xcode on his Mac.

## Notes

Spike code and run sheet: [../../spike-009/](../spike-009/RUN.md). The same run also covers spec 005 §12 Q2 (does the helper need Full Disk Access added by hand), Q4 (Wi-Fi SSIDs as root) and Q6 (Personal Team certificate lifetime). Q3 (App Management) stays with 008; Q5 (Touch ID on a custom right) is skipped for now.

## Resolution

Results: [spike-009/RESULTS.md](../spike-009/RESULTS.md) (run on John's Mac, macOS 26.7.1, 2026-11-07).
Free Personal Team signing works: SMAppService.daemon registers, is approved once in Login Items, and runs as uid 0 over XPC with a team-pinned code-signing requirement. Rebuilds with the same identity need no re-approval, but the app must restart the helper to load a new binary. The helper inherits the app's Full Disk Access (no manual entry). Ad hoc signing fails (launchd EX_CONFIG while status says enabled), so spec 005 Plan B is ruled out. Also answers spec 005 §12 Q2 (no), Q4 (yes) and Q6 (1-year cert). Setup gotcha: install Apple's WWDR G3 intermediate or signing fails.

Follow-ups for 005: drop Plan B; app must restart the helper after an update (version handshake + unregister/register or kickstart); builder setup must check for the WWDR G3 intermediate; renewal re-approval (yearly) still untested.
