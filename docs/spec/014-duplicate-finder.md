# Spec 014: Duplicate finder

Ticket: [014](../planning/tickets/014-duplicate-finder.md) (agreed with John, 2026-11-07; this file restates its Resolution as a spec for the handoff). Code: `DiskAnalysis` (spec 016 §3). Screen: My Clutter › Duplicates (spec 007 §2, §4).

1. **Matching:** group by exact size, then SHA-256 of the first and last 16 KB, then full-file SHA-256 (CryptoKit). Only full-hash matches are duplicates. No name or date matching.
2. **APFS clones:** shown, flagged "Shares space, frees ~0 KB", unticked, and excluded from the "you can free" total (detect via `ATTR_CMNEXT_CLONEID` / allocated-size check). **Hard links** (same inode) count as one file and are never duplicates.
3. **Default scope:** `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, plus **Add Folder…**. External volumes only when added.
4. **Always skipped:** `~/Library`; packages and bundles as opaque units (Photos/Music libraries, `.app`, `.xcodeproj`, …); iCloud Drive and `~/Library/CloudStorage`; hidden files; `.git` folders; files under **1 MB** (minimum adjustable in Settings). The protected floor (spec 006 §5) still applies.
5. **Removal** always goes to the Trash, logged as rule `manual`.
6. **Auto-select keeps** the copy outside Downloads/Desktop first; tie-break oldest creation date, then shortest path. Picker: Keep Oldest / Keep Newest / Choose Myself. The last copy in a set can never be ticked.
7. **Hash cache:** `~/Library/Application Support/TidyMyMac/Cache/hashes.sqlite` (SQLite via the system `libsqlite3`, no package) keyed on path + size + modification date + inode; stale entries replaced on change; **Clear Cache** in Settings.
8. **Duplicate downloads:** same engine, source limited to `~/Downloads`, matched against copies anywhere in the scanned folders. "Also elsewhere" appears only on a real hash match, never on `file (1).pdf` name patterns alone.
