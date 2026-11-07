---
id: 010
title: Design the logo and visual identity
type: wayfinder:prototype
status: closed
assignee: claude-010
blocked_by: []
---

## Question

What do TidyMyMac's app icon and visual identity look like? John wants it to look like a professionally developed app. Produce a few original icon directions in the macOS icon style (rounded-square, layered, light and dark variants), plus a colour palette, typography (SF Pro) and accent style for John to choose from. No CleanMyMac or MacPaw assets, colours or look-alikes. Output: icon source files and an `.icns`/asset-catalog-ready set, and a short style guide that ticket 007 uses.

## Notes

Drafted 2026-11-07, waiting for John to pick a direction. Everything is in [../../design/](../../../design/style-guide.md):
- Three icon directions (A Sweep, recommended; B Stack; C Ring) as SVG, light and dark, plus full-bleed background/foreground layers for Icon Composer: `design/icons/`.
- 1024 PNG renders: `design/png/`. Xcode `AppIcon.appiconset` and `TidyMyMac.icns` per direction: `design/build/`.
- Style guide shared by all three (only the accent changes): [style-guide.md](../../../design/style-guide.md).
- Preview page: `design/preview.html` (also published as an artifact for John).
- Generators: `design/src/make_icons.py`, `make_sets.py`, `make_preview.py` (re-run after tweaks).

## Resolution

John picked **A, Sweep** (2026-11-07): a teal brush stroke with sparkles. Accent `AccentColor` = Tidy Teal `#0C7D75` (light) / `#3DD9C5` (dark), mint `#DDFBF4` for fills. Final assets: `design/icons/a-sweep/` (SVG + Icon Composer layers) and `design/build/a-sweep/` (AppIcon.appiconset, TidyMyMac.icns). Everything else follows [style-guide.md](../../../design/style-guide.md). B and C stay in the folder as discarded alternatives.

Follow-ups (folded into ticket 007 and the build, no new tickets): a monochrome menu bar template of the sweep glyph, and building `AppIcon.icon` in Icon Composer on John's Mac.
