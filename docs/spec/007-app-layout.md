# Spec 007: App layout and screen flow

Ticket: [007](../planning/tickets/007-app-layout-prototype.md). Prototype: [design/prototype/tidymymac-layout.html](../../design/prototype/tidymymac-layout.html) (published as an artifact for John). Visual rules: [design/style-guide.md](../../design/style-guide.md). Feature scope: v1 Keep column of [the feature list](../planning/cleanmymac-feature-list.md).

Status: approved by John (2026-11-07, "Looks good").

## 1. Window

- One main window: `NavigationSplitView` with a sidebar of modules and a detail column. Default 1100 × 720, minimum 900 × 600; size and selected module are remembered.
- Each module puts its title (and a one-line subtitle such as "47.2 GB found") in the window toolbar. Module-level switches (tabs) are a segmented `Picker` in the toolbar.
- The primary action sits in a **footer bar** at the bottom of the detail column: a live summary on the left ("1,284 items · 1.3 GB to Trash · 7.7 GB deleted permanently · 1 task"), buttons on the right, the prominent one rightmost. Toolbar holds secondary actions (Scan Again, Ignore List, Choose Folder…, search).

## 2. Sidebar (9 modules, 3 groups)

| Group | Module | Contents |
|---|---|---|
| (top) | Tidy Up | One scan → results → review → clean → done |
| (top) | Health | Health summary, storage (purgeable read-only), Trash size, setup status, run history, reminders (rules in [spec 012](012-health-and-reminders.md); reminder default is every 2 weeks, not the prototype's weekly) |
| Clean up | Cleanup | Category list + detail (rule's Removes / Keeps / Goes to / source) + item table |
| Clean up | Declutter | Tabs: Large & Old · Duplicates · Downloads (duplicate downloads flagged inline as "Also elsewhere") |
| Clean up | Disk Map | Breadcrumb, disk/folder picker, treemap (two levels deep) + size-ranked list with ticks |
| Maintain | Applications | Tabs: Uninstaller · Unused · Leftovers · Installers · Updates (check only) |
| Maintain | Performance | Tabs: Maintenance (DNS, Spotlight, TM snapshots) · Login Items · Background Items |
| Maintain | Protection | App permissions, read-only, with "Open in System Settings" |
| (bottom) | My Tools | Grid of 24 single-purpose tools; each opens the matching module/tab. It is a launcher, not a separate engine |

- After a scan, rows show a trailing figure (Cleanup "35.4 GB", Applications "2 updates").
- Sidebar footer: setup status ("Full Disk Access on · Helper ready", orange dot when not) that opens first-run setup, and free disk space that opens Health.
- Symbols per style guide §6. Disk Map is a **treemap**, not a bubble map, to keep the look our own.

## 3. Tidy Up flow

1. **Idle:** app icon, one line on what it checks, large Scan button, chips naming the areas, last run.
2. **Scanning:** progress ring + running "found so far" size + per-area checklist. Stop returns to the previous state.
3. **Results:** hero number (selected to clean) + "free space after cleaning" bar, then six cards:
   - Actionable: **Cleanup** (caches, logs, Xcode junk, AI tool caches, broken login items), **Trash** (starts unticked, permanent), **Applications** (leftovers of deleted apps; update count links to Updates), **Maintenance** (tasks with ticks; DNS on, Spotlight and snapshots off).
   - Look only: **Declutter** (large/old files count, opens module), **Protection** (permission counts, opens module). Personal files are never cleaned by Tidy Up.
   - Footer: summary + Dry Run + Review All… + Clean N GB. The review sheet has Dry Run too; it lists the same items and tasks Clean would do, changing nothing.
4. **Review sheet:** grouped list with disclosure per category, tri-state group checkbox, item rows (name, path in mono with middle truncation, risk badge, destination Trash/Delete, size), a filter (All · Cleanup · Trash · Leftovers · Tasks) and the same live summary in its footer.
5. **Confirm alert:** title "Clean 11,724 items?"; body states Trash vs permanent amounts, tasks, and that macOS asks for the admin password once. Button names the effect ("Clean 9.0 GB"; "Delete …" in red when nothing goes to Trash).
6. **Cleaning:** same ring, "freed so far".
7. **Done:** green check, amount freed, how much is in the Trash, View Run Log (→ Health) and Done.

Risk handling follows spec 006: safe ticked, caution unticked, risky (iOS backups, local AI models) **never in Tidy Up**; in Cleanup a risky category has no select-all and shows a warning note.

## 4. Shared patterns

- **Review before delete everywhere:** every destructive button opens one confirmation that names the count, the size and where it goes. Module footers show the same summary line as Tidy Up.
- **Destination column:** `trash` (secondary) or `Delete` with a flame symbol (red), from each rule's action.
- **Admin badge** on categories/tasks that go through the helper.
- **Empty state:** 48 pt symbol, one line, one action (e.g. "Nothing left to remove in User Caches." + Scan Again).
- **Item tables** (Cleanup, Declutter's Large & Old and Downloads, the Uninstaller's related files, Run History) sort by any column with a value; until a header is clicked they keep their natural order. Tables with ticks have **Check All / Check None** above them, plus the Tidy Up review sheet. Both act only on the rows shown (after filters), and Check All never ticks risky items: those are ticked one by one.
- **Toasts** for completed one-off actions ("Moved 3 files to the Trash").
- Duplicates: auto-select picker (Keep Newest / Oldest / Choose myself); the app refuses to tick the last copy in a set.
- Uninstaller: detail pane lists every related file; Uninstall… opens a sheet with ticks (the .app itself always included) and "Move to Trash".
- Updates: rows show current → available version and "Open App"; macOS row opens Software Update. Nothing is installed.

## 5. Menu bar extra

Template glyph of the sweep (monochrome). Popover: status pill, CPU (sparkline), Memory (used / total + pressure), Storage (free + bar), Network (↓/↑). Alerts: low disk space and Trash over a size, each a switch. Buttons: Open TidyMyMac, Run Tidy Up.

## 6. First run

Sheet over the window: icon, one paragraph, two steps: (1) Allow Full Disk Access → Open System Settings, (2) Approve the helper → Install Helper (enabled after step 1). Later / Get Started. Re-opened from the sidebar status line or Health.

## 7. Left for the build

- Real app icons in lists (prototype uses letter placeholders).
- Liquid Glass is drawn by macOS 26; the sketch only hints at it.
- Keyboard: ⌘R scan, Space quick-looks a row, ⌫ moves the selection to the review list (to be confirmed in the build).
