---
id: 007
title: Sketch the app's layout
type: wayfinder:prototype
status: closed
assignee: thread "Sketch TidyMyMac app layout"
blocked_by: [001, 010]
---

## Question

How should TidyMyMac look and flow: sidebar of modules, the Smart Care scan-and-review screen, and the review-before-delete pattern? Produce a rough clickable prototype in our own visual style (no CleanMyMac assets) for John to react to.

John (2026-11-07): it must look professionally designed. Follow Apple's Human Interface Guidelines and native SwiftUI patterns, use the visual identity from ticket 010, and cover only the v1 Keep features from ticket 001.

## Resolution

Built a clickable prototype (2026-11-07): [design/prototype/tidymymac-layout.html](../../../design/prototype/tidymymac-layout.html) (`source.html` beside it has the readable code), written up as [spec 007](../../spec/007-app-layout.md).

- Window: `NavigationSplitView`, inset sidebar, module tabs as a segmented picker in the toolbar, primary action in a footer bar with a live "items · to Trash · deleted permanently · tasks" summary.
- Sidebar: Smart Care, Health; Clean up (Cleanup, My Clutter, Space Lens); Maintain (Applications, Performance, Protection); My Tools (a launcher grid of 24 tools). Setup status and free space in the sidebar footer.
- Smart Care: idle → scanning ring → six result cards (four actionable, My Clutter and Protection look-only) → grouped review sheet → one confirmation that names Trash vs permanent and the admin password → done screen linking to the run log. Risky items never appear.
- Space Lens uses a two-level treemap plus a size-ranked list, not a bubble map, so the look is our own.
- Menu bar popover with 4 monitors and 2 alert switches; first-run sheet with Full Disk Access and helper steps.

Follow-ups: none new. John approved the sketch as is (2026-11-07); real app icons, keyboard shortcuts and Liquid Glass are left for the build.
