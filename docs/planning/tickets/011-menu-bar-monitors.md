---
id: 011
title: Decide how the menu bar monitors get their numbers
type: wayfinder:grilling
status: closed
assignee: claude (thread: Decide menu bar monitor details)
blocked_by: []
---

## Question

For the 4 menu bar monitors and 2 alerts kept in ticket 001: which public API feeds each one (host_statistics, IOKit, getifaddrs, URL resource values...), how often each refreshes when the menu is open vs closed, and what thresholds trigger the alerts — keeping energy use negligible. Bring a recommended default for each so John only confirms or changes it.

## Resolution

Agreed with John (2026-11-07). Full detail in [spec 011](../../spec/011-menu-bar.md).
- The menu bar extra lives in the main app (`MenuBarExtra`, window style). Show in menu bar is on; Open at login is off. The bar shows the glyph only, with a dot while an alert is active.
- Sources (public, no root): CPU `host_statistics` load ticks; memory `host_statistics64` VM pages, `hw.memsize` and the pressure level; storage "important usage" available capacity; network `NET_RT_IFLIST2` 64-bit counters on physical `en*` interfaces; Trash size via enumerator (needs FDA).
- Refresh: with the popover open, CPU and network 1 s, memory 2 s, storage 30 s. Closed: nothing but alert checks. Paused on sleep or lock.
- Low disk alert below the shared low-disk setting (20 GB default; 10/20/50), which is also Health's orange line (ticket 012). Checked every 5 min, on wake and after cleanups. Fires once per crossing, re-arms at +5 GB or after 24 h.
- Full Trash alert over the shared Trash setting (5 GB; 1/5/10/20), measured on Trash change. Disabled without FDA. The button only opens the app.
- Rows open Activity Monitor or Space Lens. The top-apps list is Later.
