# Rule credits

Every rule records its `source` (spec 006 §3, §7). This file lists each source project, its URL, the commit used, its licence and what we took. Full licence texts go in `ThirdPartyLicenses/`.

Allowed licences: `own`, `MIT`, `Apache-2.0`. Learn-only (never copied): Mole, BleachBit, Pearcleaner, Latest.

## Current rule set (milestone 1)

Every rule is `origin: own`: written from Apple's documentation of the Library folder layout and from observation on a Mac, not copied from another project. The seed table in spec 006 §6 names ClearDisk, mac-cleanup-py and PureMac as places to cross-check; when a rule takes paths or wording from one of them, its `source` names it with the commit, and the project is listed here with its licence text in `ThirdPartyLicenses/`.

`ai.caches` (AI app caches from PureMac's category list) is not in this set yet; it lands when that list is read and credited.

## Code reused in the Applications module (milestone 4)

| Project | URL | Commit | Licence | What we took |
|---|---|---|---|---|
| Sparkle | https://github.com/sparkle-project/Sparkle | `14fdbf28dc7c` (2.x) | MIT, `ThirdPartyLicenses/Sparkle.txt` | `SUStandardVersionComparator` ported to Swift (`AppInventory/VersionComparator.swift`) with its unit tests; appcast field names and the update filters of `SUAppcastDriver` (spec 013 §3–4) |
| Homebrew (brew) | https://github.com/Homebrew/brew | `67984c752d13` (master, 2026-11-07) | BSD-2-Clause, `ThirdPartyLicenses/Homebrew.txt` | The approach of the livecheck `Sparkle` and `ElectronBuilder` strategies (enclosure attributes before elements; `latest-mac.yml` top-level `version`). Our code is written from scratch; no Ruby was copied. The cask catalogue itself is fetched from formulae.brew.sh at run time, never bundled. |

Learn-only, not copied: Latest (GPL-3.0), Pearcleaner (Apache-2.0 + Commons Clause).
