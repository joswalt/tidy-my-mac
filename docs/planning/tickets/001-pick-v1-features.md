---
id: 001
title: Pick the v1 features
type: wayfinder:grilling
status: closed
assignee: thread "Pick TidyMyMac v1 features"
blocked_by: []
---

## Question

Which features from the catalogue make TidyMyMac v1, which are Later, and which are dropped? Work through each module with John using the Keep? column in ../cleanmymac-feature-list.md.

## Resolution

Agreed with John on 2026-11-07, in four batches. Every row of [../../cleanmymac-feature-list.md](../cleanmymac-feature-list.md) now has Keep, Later or Drop.

**v1 (Keep):**
- Smart Care: one-click scan; review before run.
- Cleanup: user and system caches, user and system logs, Xcode junk, AI junk, local AI models (review only), iOS backups (review only), Trash bins, broken login items, ignore list / safety database.
- Protection: app permissions (read-only list, with links to System Settings).
- Performance: flush DNS, reindex Spotlight, thin Time Machine snapshots (these three use the admin helper), login items, background items.
- Applications: uninstaller, unused apps, leftover files, installer leftovers, Sparkle and macOS update check (check only, no installing; App Store detection left out).
- My Clutter: large and old files, duplicates, Downloads review, duplicate downloads.
- Space Lens: storage map, size-ranked list, scan one folder or drive.
- My Tools: tool shortcuts (each module runs on its own from the sidebar).
- Health: simple health summary, run history from the run log, scheduled reminders (notification only, never unattended deletion).
- Menu bar: CPU/RAM/storage/network monitors; alerts for low disk space and full Trash only.
- Platform: admin helper, Full Disk Access onboarding, undo safety.

**Later:** malware scan, real-time monitor, protection status, Cloud Cleanup (both), document versions, Mail attachments, broken preferences, deleted users, browser privacy, recent items, updating non-Sparkle apps, extensions manager, similar images, pinned tools/workflows, screen cleaning mode, recommendations assistant, battery and connected-device monitors, other alerts.

**Drop:** language file stripping, universal binary stripping, repair permissions, Free up RAM, periodic scripts, Shredder, Speed up Mail, Wi-Fi network removal, licensing. Purgeable space is shown only as a read-only figure.

**Added requirement (John, 2026-11-07):** the app must have a good-looking logo and a polished, professional design. Tracked in ticket 010 and folded into ticket 007.
