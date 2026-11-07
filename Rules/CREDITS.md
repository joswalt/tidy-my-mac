# Rule credits

Every rule records its `source` (spec 006 §3, §7). This file lists each source project, its URL, the commit used, its licence and what we took. Full licence texts go in `ThirdPartyLicenses/`.

Allowed licences: `own`, `MIT`, `Apache-2.0`. Learn-only (never copied): Mole, BleachBit, Pearcleaner, Latest.

## Current rule set (milestone 1)

Every rule is `origin: own`: written from Apple's documentation of the Library folder layout and from observation on a Mac, not copied from another project. The seed table in spec 006 §6 names ClearDisk, mac-cleanup-py and PureMac as places to cross-check; when a rule takes paths or wording from one of them, its `source` names it with the commit, and the project is listed here with its licence text in `ThirdPartyLicenses/`.

`ai.caches` (AI app caches from PureMac's category list) is not in this set yet; it lands when that list is read and credited.
