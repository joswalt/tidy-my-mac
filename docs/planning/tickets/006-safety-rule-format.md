---
id: 006
title: Decide the safety rule format and source
type: wayfinder:grilling
status: closed
assignee: thread "Decide cleanup rule format"
blocked_by: [001, 003]
---

## Question

What does a safety rule look like (file format, fields, Trash vs delete, age/size conditions), where does the initial rule set come from, and how are rules reviewed before they ship?

## Resolution

Spec: [specs/006-safety-rules.md](../../spec/006-safety-rules.md) (2026-11-07). John chose: Pearcleaner stays learn-only; three risk levels.
- Rules are bundled JSON (kinds: clean, leftover-location, protect, app-override), checked by a JSON Schema and loaded with Codable; no downloaded rules.
- `delete` only for cache/log categories; everything else Trash or a named operation; helper rules name a zone from spec 005 and inherit its action.
- Risk: safe (ticked), caution (unticked), risky (never in Smart Care, ticked one by one); iOS backups and local AI models are risky.
- A code-level protected floor no rule can override; path containment, fresh re-check, allocated sizes, dry run, per-item run log.
- Seed rules for every kept v1 feature listed in §6, from Apple docs, ClearDisk, mac-cleanup-py, app-cleaner.sh and PureMac, gap-checked against Mole.
- Review: lint, fixture tests, `experimental` until a dry run on John's Mac, then `verified`; CREDITS.md + licence texts.
