---
id: 017
title: Decide the end-to-end test plan
type: wayfinder:grilling
status: closed
assignee: claude (thread: Plan TidyMyMac testing and safety)
blocked_by: [016]
---

## Question

Beyond the per-rule lint, fixtures and dry run in spec 006: how do we test that nothing outside the selected items is ever touched (fixture home folders, a throwaway user account or VM, helper tests), what runs in CI vs only on John's Mac, and what must pass before a release build? Include the three one-minute Mac checks listed at the end of research/015-detect-full-disk-access.md, and the softwareupdate -l timing check from research/013-app-update-checks.md.

## Resolution

Agreed with John, 2026-11-07 (all recommended defaults accepted). Full plan: [specs/017-test-plan.md](../../spec/017-test-plan.md).

- Core property: snapshot-diff end-to-end test; removed set must equal selected set, tripwires in every protected-floor folder untouched, run log matches.
- Layers: temp-dir fixtures for all automated tests (`TestHome` refuses non-temp roots, safety lint bans direct home/delete APIs); throwaway standard user `tidytest` for real runs; John's own account dry runs only. No VM; helper zones tested with canary files.
- CI: GitHub Actions on pull requests, unsigned, no secrets. Signed build, real helper, FDA and the `tidytest` run are on John's Mac (`scripts/check-local.sh` + checklist).
- No XCUITest and no coverage percentage; named required cases instead.
- Release gate: short form always; full form when SafetyFloor, HelperCore, Helper, RuleEngine or `Rules/` change; no override.
- One-minute checks (015 FDA live grant, deep links, helper sees grant; 013 `softwareupdate -l` timing) run in the first-build checklist; shell-only ones in [research/017-mac-checks.sh](../research/017-mac-checks.sh).

Follow-ups: none new; ticket 018 adds §8's files to the repo layout.
