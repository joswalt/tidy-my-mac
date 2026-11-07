---
id: 014
title: Decide how the duplicate finder matches and auto-selects
type: wayfinder:grilling
status: closed
assignee: claude (thread: Define duplicate finder rules)
blocked_by: []
---

## Question

How does the duplicate finder decide two files are the same (size then partial hash then full hash, which hash), how does it treat APFS clones (research 004: deleting a clone may free nothing), which folders it scans by default, and which copy auto-select keeps (oldest, newest, shortest path, outside Downloads)? Bring a recommended default for each.

## Resolution

Agreed with John, 2026-11-07 (all recommendations accepted).

1. **Matching:** group by exact size, then SHA-256 of the first and last 16 KB, then full-file SHA-256. Only full-hash matches are duplicates. No name or date matching.
2. **Hash:** SHA-256 via CryptoKit; no third-party dependency.
3. **APFS clones:** shown, flagged "Shares space, frees ~0 KB", unticked, and excluded from the "you can free" total (detect via `ATTR_CMNEXT_CLONEID` / allocated-size check). Hard links (same inode) count as one file and are never duplicates.
4. **Default scope:** home folder (Desktop, Documents, Downloads, Pictures, Movies, Music) plus "Add Folder…". External volumes only when added.
5. **Always skipped:** `~/Library`, packages/bundles treated as opaque (Photos/Music libraries, `.app`, `.xcodeproj`, etc.), iCloud and `~/Library/CloudStorage`, hidden files, `.git` folders, files under 1 MB (minimum adjustable in Settings). Protected floor (spec 006) still applies; removal always goes to the Trash.
6. **Auto-select keeps:** the copy outside Downloads/Desktop first; tie-break oldest creation date, then shortest path. Picker: Keep Oldest / Keep Newest / Choose Myself (spec 007). The last copy in a set can never be ticked.
7. **Cache:** hash cache in Application Support keyed on path + size + modification date; entries invalidated on change; "Clear cache" in Settings.
8. **Duplicate downloads:** same engine, limited to `~/Downloads` as the source, matched against copies anywhere in the scanned folders. "Also elsewhere" appears only on a real hash match, never on name patterns like `file (1).pdf` alone.
