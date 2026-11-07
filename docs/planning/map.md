---
label: wayfinder:map
title: TidyMyMac v1
---

## Destination

A build-ready spec for **TidyMyMac v1**, a native Mac cleaner modelled on CleanMyMac's features. Every decision a builder would otherwise have to ask is settled. Then it is handed off to coding.

## Notes

- Domain: macOS system utility; personal use on John's Apple Silicon Macs, kept open to a free direct download later. Not the Mac App Store.
- Stack: Swift + SwiftUI, macOS 14 Sonoma or newer, Apple Silicon only.
- v1 includes an **admin helper** for system-level tasks. John has **no paid Apple Developer account**.
- Deletion: to the Trash by default; caches and logs are deleted permanently; every run is logged.
- Safety rules: our own list, from Apple docs, checked against open-source cleaners; MIT rule sets may be reused with credit.
- **Clean-room:** never decompile, download or inspect CleanMyMac binaries. rea (morluto/rea) may be used only on open-source cleaners.
- Feature catalogue: [cleanmymac-feature-list.md](cleanmymac-feature-list.md). Glossary: [CONTEXT.md](CONTEXT.md).
- Skills for grilling tickets: grilling + domain-modeling. Research tickets: research.

## Decisions so far

- Destination, audience, clean-room stance, v1 = core subset, map as local markdown (agreed with John, 2026-11-07, chart session round 1)
- Swift/SwiftUI, Apple Silicon + macOS 14+, admin helper in v1, Trash-by-default deletion, own rule list (agreed with John, 2026-11-07, chart session round 2)
- [Open-source Mac cleaners and their rule licenses](tickets/003-open-source-cleaner-rules.md): seed our rules from ClearDisk, mac-cleanup-py, app-cleaner.sh and PureMac (permissive, with credit); Mole and Pearcleaner are learn-only.
- [What each CleanMyMac-style feature needs from macOS](tickets/004-feature-privilege-needs.md): Full Disk Access matters more than root; language/binary stripping and repair permissions are harmful, Free RAM/periodic scripts/Shredder/purgeable are obsolete, several features rely on private data.
- [Installing an admin helper without a paid developer account](tickets/002-helper-without-dev-account.md): SMAppService daemon + XPC helper with an allow-list, signed with the free Personal Team identity; osascript only as a fallback.
- [Check three permission questions on a real Mac](tickets/008-verify-on-real-mac.md): App Management blocks edits inside other developers' apps but not trashing them; `tccutil reset` needs no root; listing or sizing ~/.Trash needs Full Disk Access, moving items into it doesn't (tested on macOS 26.7.1).
- [Pick the v1 features](tickets/001-pick-v1-features.md): 53 features Keep, 19 Later, 10 Drop (see the Keep column); updates are check-only, scheduling is reminders only, the menu bar has 4 monitors and 2 alerts. John added: a polished, professional design and logo (ticket 010).
- [Decide the safety rule format and source](tickets/006-safety-rule-format.md): bundled JSON rules ([spec](../spec/006-safety-rules.md)); delete only caches/logs, else Trash; three risk levels (safe/caution/risky); code-level protected floor; rules go experimental → verified after a dry run on John's Mac; Pearcleaner stays learn-only (John).
- [Prove the admin helper works with free signing](tickets/009-prove-helper-free-signing.md): proven on John's Mac; Personal Team-signed daemon runs as root, survives rebuilds without re-approval, inherits the app's Full Disk Access; ad hoc signing fails, so no Plan B.
- [Design the logo and visual identity](tickets/010-logo-and-visual-identity.md): icon "Sweep" (teal brush stroke and sparkles), Tidy Teal accent, native HIG style guide in design/style-guide.md (John picked, 2026-11-07).
- [Design the admin helper](tickets/005-admin-helper-design.md): on-demand SMAppService daemon, Personal Team signed; helper scans 6 fixed zones and only acts on its own handles (app never sends paths); typed allow-list, admin password once per run, root-owned items to John's Trash with restore ([spec](../spec/005-admin-helper.md); John, 2026-11-07).
- [Sketch the app's layout](tickets/007-app-layout-prototype.md): 9 sidebar modules in 3 groups (My Tools is a launcher), Smart Care = scan → six result cards → grouped review sheet → one confirm naming Trash vs permanent → done; Space Lens is a treemap; first-run sheet for FDA + helper ([spec](../spec/007-app-layout.md), [prototype](../../design/prototype/tidymymac-layout.html); John approved, 2026-11-07).
- [How to detect missing Full Disk Access reliably](tickets/015-detect-full-disk-access.md): probe ~/.Trash, Safari, Mail with a real directory read, re-check on app activation, deep-link to the FDA pane, restart the helper after a grant.
- [How to find and compare app update feeds](tickets/013-app-update-checks.md): own feed checker for Sparkle and Electron feeds with Homebrew as fallback, Sparkle's version comparator ported, macOS updates via a timed `softwareupdate -l` on request, never touching other apps' settings.
- [Decide the repo layout and module boundaries](tickets/016-repo-layout-and-modules.md): private repo `joswalt/tidy-my-mac` (John creates it), XcodeGen, thin SwiftUI app + root helper + one local package of 9 libraries, rules in top-level `Rules/`, menu bar in the app process, no third-party packages, handoff = `docs/spec/README.md` index ([spec](../spec/016-repo-layout.md); John, 2026-11-07).
- [Decide how the duplicate finder matches and auto-selects](tickets/014-duplicate-finder.md): size → 16 KB head/tail SHA-256 → full SHA-256; APFS clones flagged unticked and not counted, hard links = one file; scans home media folders + added folders, skips Library/packages/cloud/hidden/<1 MB; auto-select keeps the copy outside Downloads/Desktop, then oldest, then shortest path; hash cache; duplicate downloads share the engine (John, 2026-11-07).
- [Decide the end-to-end test plan](tickets/017-test-plan.md): snapshot-diff end-to-end test with tripwires in protected folders, temp-dir fixtures + throwaway `tidytest` user (no VM, canaries for helper zones), CI on PRs unsigned, signed/helper/FDA checks on John's Mac, short/full release gate, one-minute checks at first build ([spec](../spec/017-test-plan.md); John, 2026-11-07).
- [Decide how the menu bar monitors get their numbers](tickets/011-menu-bar-monitors.md): menu bar lives in the main app (glyph only, alert dot); public Mach/sysctl/URL-resource sources, sampled only while the popover is open; low-disk alert at a shared 20 GB setting (Health orange line), Trash alert at 5 GB (needs FDA) ([spec](../spec/011-menu-bar.md); John, 2026-11-07).
- [Decide the health summary and reminders](tickets/012-health-summary-and-reminders.md): three-state status (no score) from six signals, worst wins; disk and Trash lines shared with the menu bar alerts (20 GB / 5 GB, red at 10 GB); reminders are notifications counted from the last Smart Care, every 2 weeks at 10:00 by default ([spec](../spec/012-health-and-reminders.md); John, 2026-11-07).
- [Assemble the v1 build spec](tickets/018-assemble-v1-spec.md): one index ([specs/README.md](../spec/README.md)) over all specs, gaps settled (run log, restore, ignore list, Trash bins, unused 90 days, Space Lens, login items, settings), Protection = privacy-pane links only, 8-milestone build order; destination reached, coding waits for the repo and John's go (John signed off, 2026-11-07).

## Not yet specified

- Nothing left in the fog: every remaining area is now a ticket (011 to 018).

## Out of scope

- Mac App Store edition (sandbox blocks too many features).
- Decompiling or inspecting CleanMyMac (EULA and code-taint risk).
- Malware scanning and Cloud Cleanup in v1 (marked "Later").
- Subscriptions, licensing and payments.
