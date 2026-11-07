---
id: 012
title: Decide the health summary and reminder settings
type: wayfinder:grilling
status: closed
assignee: claude (thread: Decide health summary and reminders)
blocked_by: []
---

## Question

Which signals feed the Smart Care health summary (which rules, free-space level, pending updates, helper/FDA status) and how they combine into a status shown to John; and for v1's reminder-only scheduling, what the default cadence is, what triggers a reminder, and which settings John can change. Uses spec 007 for the screens.

## Resolution

Agreed with John, 2026-11-07 (all recommendations accepted). Full detail in [spec 012](../../spec/012-health-and-reminders.md).

- Health shows a three-state status (Looks good / Worth a look / Needs attention), no score; overall = worst of six signals: free space, last Smart Care, junk found last time, Trash size, Full Disk Access, admin helper. Updates are shown but don't affect status.
- Free-space orange line and Trash line are shared with the menu bar alerts (ticket 011): low disk default 20 GB, red fixed at 10 GB in Health only; Trash 5 GB.
- Refreshes on launch, on opening Health and after runs; no background scans.
- Reminders: local notification counted from the last Smart Care run, default every 2 weeks at 10:00 (weekly/2 weeks/monthly), one repeat after 3 days, click starts a scan, "Tomorrow" snoozes. Permission asked on the first Smart Care Done screen. Settings in Health and ⌘,.
