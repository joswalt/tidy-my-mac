---
id: 003
title: Open-source Mac cleaners and their rule licenses
type: wayfinder:research
status: closed
assignee: claude-research
blocked_by: []
---

## Question

Which open-source Mac cleaners (e.g. Pearcleaner, Mole, AppCleaner alternatives, BleachBit's macOS cleaners, mac-cleanup scripts) have reusable cleanup/uninstall rule sets? For each: license, rule format, coverage, maintenance status, and whether MIT-compatible reuse with credit is allowed.

## Resolution

Findings: [research/003-open-source-cleaner-rules.md](../research/003-open-source-cleaner-rules.md).
Copy with credit: ClearDisk (MIT), mac-cleanup-py (Apache-2.0), sunknudsen app-cleaner.sh (MIT), PureMac categories/scan paths (MIT). Learn only: Mole (GPL-3.0, best safety model), Pearcleaner (Apache 2.0 + Commons Clause, on hold), PureMac's uninstall Conditions/Locations (look derived from Pearcleaner), BleachBit/CleanerML (GPL, format ideas). Recommendation: own rule format filled from the permissive sources plus a CREDITS file, gap-checked against Mole.
