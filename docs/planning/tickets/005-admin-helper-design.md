---
id: 005
title: Design the admin helper
type: wayfinder:grilling
status: closed
assignee: thread "Design the admin helper"
blocked_by: [001, 002, 004, 009]
---

## Question

Given the chosen v1 features and the install options found, how is the admin helper installed and what exact set of operations may it perform (an allow-list), so the app can never ask it to delete arbitrary paths?

## Draft (not a resolution)

Draft design with recommended options: [specs/005-admin-helper.md](../../spec/005-admin-helper.md) (2026-11-07). Still blocked on 001 (drop operations for features that are cut) and 009 (confirm Personal Team signing; plans B/C in §10 if not). Open questions in its §12 should be folded into 008 and 009. Confirm the recommended choices with John when unblocked: on-demand helper, compiled-in zones + helper-issued handles, admin password once per run (5 min), root-owned items moved to John's Trash with a restore ledger, bundle ID `io.github.joswalt.TidyMyMac`.

John confirmed (2026-11-07): admin password once per run, root-owned items to his Trash with restore ledger, bundle ID `io.github.joswalt.TidyMyMac`. Still open until 001 and 009 close.

## Resolution

Spec: [specs/005-admin-helper.md](../../spec/005-admin-helper.md) (decided 2026-11-07). John chose: admin password once per cleanup run; root-owned items go to his Trash with restore from TidyMyMac; app ID `io.github.joswalt.TidyMyMac`.
- One on-demand `SMAppService.daemon` helper in the app bundle, Personal Team signed (team `26TUUFN7M2`), XPC with team-pinned code-signing checks both ways; exits after 60 s idle.
- The app never sends a path: the helper scans 6 compiled-in zones (system caches, system logs, rotated logs, /Library launch items, /Library leftovers, root-owned apps) and only acts on handles it issued, re-checked (no symlinks, same inode, deny list) at action time.
- Typed allow-list: scan, list snapshots/receipts, Spotlight status, remove, forget receipt, flush DNS, reindex Spotlight, delete TM snapshot, enable/disable a /Library daemon, restore/empty trashed items via a root-owned ledger. No shell, no Wi-Fi, nothing harmful from research 004.
- Health check by `hello()` with timeout; after rebuilds the app restarts the helper (shutdown, else silent unregister+register, per spike 009).
- Ad hoc fallback ruled out by spike 009; osascript one-shot mode documented but not built. Builder setup must install Apple's WWDR G3 intermediate.
- Later features needing the helper (deleted users, extensions manager) listed in spec §13.
