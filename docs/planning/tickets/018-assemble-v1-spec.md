---
id: 018
title: Assemble the v1 build spec
type: wayfinder:task
status: closed
assignee: claude (thread: Assemble TidyMyMac v1 spec)
blocked_by: [011, 012, 013, 014, 015, 016, 017]
---

## Question

Pull every decision and spec into the handoff format chosen in ticket 016, check nothing is left for a builder to ask, and get John's sign-off. Closing this ticket reaches the destination.

## Resolution

Signed off by John, 2026-11-07. Build spec: [specs/README.md](../../spec/README.md) (becomes `docs/spec/README.md`), with new detailed specs [013](../../spec/013-update-checks.md), [014](../../spec/014-duplicate-finder.md) and [015](../../spec/015-full-disk-access.md) written from their research and resolutions.

- Gaps settled at assembly (§6): JSON Lines run log per run, restore from run history, `ignore.json`, Trash bins = own + external volumes (no Mail), unused apps 90 days, Large & Old ≥ 100 MB or 1 year, Downloads review, Space Lens, Login Items links to System Settings, Background Items toggles, Settings panes, SQLite hash cache, ⌘⌫ to review.
- Protection shows privacy areas with System Settings links, no per-app list (no TCC.db reads).
- Build order: 8 milestones (§7), each a PR John reviews.

Follow-ups: John creates the empty private repo `joswalt/tidy-my-mac`; then milestone 0 starts only when John says go. When the files move into the repo, fix links to `../tickets/` and `../../` to point at `docs/planning/` and the repo root.
