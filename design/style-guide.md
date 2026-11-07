# TidyMyMac style guide (v1)

The look for TidyMyMac: a native macOS app that follows Apple's Human Interface Guidelines, looks like it shipped from a small, careful studio, and never borrows from CleanMyMac or MacPaw (no magenta or purple gradients, no iMac or monitor glyph, no illustrated mascots).

**Chosen: direction A, Sweep (John, 2026-11-07).** Three icon directions are in [icons/](icons/) with previews in [png/](png/); B and C are kept only for reference. Everything below is shared by all three; only the **accent** changes with the icon John picks (section 2).

## 1. Principles

1. **Native first.** Stock SwiftUI controls, system fonts, system materials, SF Symbols. No custom window chrome, title bars or scroll bars. On macOS 26 the system draws Liquid Glass for toolbars and sidebars by itself; we do not paint our own glass.
2. **Calm and trustworthy.** The app deletes files, so it should feel like a careful tool, not a game. Colour is used sparingly: one accent, plus status colours only where they mean something.
3. **Show, then act.** Every destructive step shows what will happen (size, count, where it goes: Trash or permanent) before the button that does it.
4. **One accent.** The accent marks the primary action and selection. Everything else is neutral system colour.

## 2. Accent colour (pick with the icon)

| Direction | Accent (light) | Accent (dark) | Secondary tint | Feel |
|---|---|---|---|---|
| **A. Sweep** (CHOSEN by John, 2026-11-07) | Tidy Teal `#0C7D75` | `#3DD9C5` | Mint `#DDFBF4` (fills) | Fresh, clean, friendly |
| **B. Stack** | Night Indigo `#2A3B6E` with Coral `#C4432A` for action buttons (icon uses brighter `#F2603F`) | Coral `#FF8E6E` | Amber `#F7AE3B` | Organised, warm, a bit playful |
| **C. Ring** | Mint `#14B8A6` → Lime `#A3E635` gradient (icon and hero ring only); flat accent `#0E8174` | `#2DD4BF` | Graphite `#2B3038` | Technical, precise, "pro tool" |

All accents were chosen to pass WCAG AA (4.5:1) for white text on the light value and for the dark value on the dark window background. Set the accent once as `AccentColor` in the asset catalog (Any + Dark appearances) and use `.tint(.accentColor)`; never hard-code hex in views.

## 3. Status colours (shared)

Use **system** colours so they adapt to light, dark and Increase Contrast automatically. They map to the three safety-rule risk levels (ticket 006):

| Meaning | SwiftUI | Used for |
|---|---|---|
| Safe | `.green` | Safe items, "all clear" health states |
| Caution | `.orange` | Caution items, review-only categories (iOS backups, AI models) |
| Risky | `.red` | Risky items, permanent deletion warnings, low disk alert |
| Info / neutral | `.secondary`, `.blue` for links | Explanations, "what is this?" popovers |

Never rely on colour alone: every status also carries an SF Symbol (`checkmark.circle.fill`, `exclamationmark.triangle.fill`, `xmark.octagon.fill`) and a word.

## 4. Typography

SF Pro only, through the system font (no bundled fonts). Use macOS text styles so the app respects the user's text size settings:

| Role | SwiftUI | Size / weight (default) |
|---|---|---|
| Module title | `.largeTitle` `.bold()` | 26 pt bold |
| Section header | `.title2` | 17 pt |
| Card title | `.headline` | 13 pt semibold |
| Body, list rows | `.body` | 13 pt |
| Secondary detail (paths, dates) | `.callout` / `.subheadline` + `.foregroundStyle(.secondary)` | 12 / 11 pt |
| Hero number ("12.4 GB to free") | `.system(size: 44, weight: .semibold, design: .rounded)` + `.monospacedDigit()` | SF Pro Rounded, the one place we use it |
| Sizes and counts in tables | `.body.monospacedDigit()` | keeps columns from jittering |
| File paths | `.callout.monospaced()` with `.truncationMode(.middle)` | |

Sizes always use `ByteCountFormatter` (`.file` style) so they match Finder.

## 5. Layout

- **Window:** `NavigationSplitView`, sidebar of modules on the left, content on the right. Minimum window 900 × 600, default 1100 × 720. Remember size and selected module.
- **Grid:** 8 pt. Content padding 20 pt; card padding 16 pt; spacing between cards 12 pt.
- **Corner radius:** cards 12 pt, small chips 6 pt, always `.continuous` style.
- **Cards:** `GroupBox` or a `RoundedRectangle` filled with `.background.secondary` (or `.regularMaterial` over imagery). No heavy shadows; a 1 pt `.separator` stroke at most.
- **Toolbar:** module actions live in the window toolbar (Scan, Review, Clean). The primary action is the rightmost toolbar button or a large `.borderedProminent` button at the bottom of a results screen.
- **Review before delete:** results in a `Table` grouped by category, with checkboxes, size column, risk badge and a "Show in Finder" button on hover. A sticky footer shows the total and where items go ("4.2 GB to Trash · 1.1 GB deleted permanently").

## 6. Sidebar and module symbols

Use SF Symbols with `.symbolRenderingMode(.hierarchical)` and the accent tint for the selected row only (default sidebar behaviour).

| Module | SF Symbol |
|---|---|
| Smart Care | `sparkles` |
| Cleanup | `bubbles.and.sparkles` |
| Protection | `lock.shield` |
| Performance | `gauge.with.dots.needle.67percent` |
| Applications | `square.grid.2x2` |
| My Clutter | `doc.on.doc` |
| Space Lens | `chart.pie` |
| My Tools | `wrench.and.screwdriver` |
| Health | `heart.text.square` |

Menu bar extra: a monochrome **template** version of the chosen icon's glyph at 18 × 18 pt (no background, no colour), so macOS tints it for light and dark menu bars.

## 7. Controls

- Primary action: `Button("Clean") {}.buttonStyle(.borderedProminent).controlSize(.large)`.
- Destructive confirmation: `.confirmationDialog` with a `role: .destructive` button whose label states the effect ("Move 312 items to Trash").
- Secondary actions: `.bordered`; tertiary: `.link` or plain.
- Progress: `ProgressView` (linear) for scans with a known total; spinner only when the total is unknown. The Smart Care hero can show a ring (direction C reuses the icon's ring).
- Empty and clean states: an SF Symbol at 48 pt in `.secondary`, one short line, one action.
- Use `.help("…")` tooltips on every icon-only button.

## 8. Motion and accessibility

- Short, purposeful motion only: 0.2–0.35 s ease-in-out, `.contentTransition(.numericText())` for counting sizes. Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`).
- Every control has an accessibility label; status colours always have a symbol and text.
- Test in light, dark, Increase Contrast and the largest text size.

## 9. Voice

Plain, calm, specific. Say what will happen and how big it is. "Moves 1.2 GB of old Xcode builds to the Trash." Not "Boost your Mac!" No fear language, no exclamation marks, no fake urgency.

## 10. App icon production

- Source: [src/make_icons.py](src/make_icons.py) generates every SVG; [src/make_sets.py](src/make_sets.py) builds the PNG sets.
- **macOS 26 (Tahoe):** open Icon Composer (ships with Xcode 26), drop in `layer-background-*.svg` and `layer-foreground-*.svg` for the chosen direction, and save `AppIcon.icon`. That gives proper Liquid Glass light, dark, clear and tinted variants. Icon Composer adds the squircle shape and glass itself, which is why the layers are full-bleed and unshaped.
- **macOS 14–15:** [build/&lt;direction&gt;/AppIcon.appiconset](build/) drops straight into `Assets.xcassets`, and `TidyMyMac.icns` is there for scripts or a non-Xcode build. These already include the squircle, shadow and gloss per the pre-Tahoe icon grid (824 pt shape on a 1024 canvas).
- Xcode 26 may generate older-OS images from the `.icon` file on its own; keep the asset catalog as the fallback until a build on John's Mac proves which one is used.

## 11. Wordmark

"TidyMyMac" set in SF Pro Display Semibold, tracking −0.5%, with "Tidy" in the accent colour and "MyMac" in `.primary`. Used in the About window and a future download page only; inside the app the window title is just the module name.
