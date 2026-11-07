---
id: 004
title: What each CleanMyMac-style feature needs from macOS
type: wayfinder:research
status: closed
assignee: claude-research
blocked_by: []
---

## Question

For every feature in ../cleanmymac-feature-list.md, what does macOS 14+ require to implement it: the public API or command used, whether it needs admin rights, Full Disk Access, other TCC permissions, or private APIs, and any known risk (e.g. stripping language files breaks code signatures).

## Resolution

Findings: [research/004-feature-privilege-needs.md](../research/004-feature-privilege-needs.md).
- Full Disk Access gates more features than root; there is no API to request it (probe a protected path, deep-link to System Settings).
- Root only for: system caches/logs, purge, mdutil -E, DNS flush, deleted users, Wi-Fi removal, /Library launch daemons, root-owned apps. Recommended via one SMAppService.daemon helper over XPC (install feasibility without a paid account is ticket 002).
- Harmful: language-file stripping, universal-binary thinning (break signatures; App Management TCC), repair permissions.
- Obsolete: Free up RAM, periodic scripts (gone in macOS 15), Shredder, free purgeable space.
- Private/undocumented data: other apps' login items, TCC permissions view, recent items, App Store updates, Bluetooth/battery health, per-app energy, hung apps; real-time malware needs an Endpoint Security entitlement.
- Caution: duplicates on APFS clones, Mail/browser cleanup, TM snapshot thinning, leftover matching.
- Open questions to verify on a real Mac → ticket 008.
