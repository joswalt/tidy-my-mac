---
id: 013
title: How to find and compare app update feeds
type: wayfinder:research
status: closed
assignee: claude-research
blocked_by: []
---

## Question

For the check-only updater (ticket 001): how can a Mac app find each installed app's Sparkle appcast (SUFeedURL in Info.plist, other places), parse it, and compare versions correctly (CFBundleVersion vs ShortVersionString, Sparkle's version comparator rules)? How do we check macOS updates without root (softwareupdate -l, its speed and side effects)? What share of typical apps have no feed, and what open-source projects (licence?) already do this?

## Resolution

Findings: [research/013-app-update-checks.md](../research/013-app-update-checks.md).
Own small Swift feed module, no embedded Sparkle: read Info.plist SUFeedURL (quotes trimmed), Electron app-update.yml, _MASReceipt → send to App Store; fall back to Homebrew cask data (BSD-2, copy with credit). Compare sparkle:version vs CFBundleVersion with a port of Sparkle's MIT comparator + its tests; apply Sparkle's OS/arch/channel filters, don't assume feed order. macOS updates: timed-out `softwareupdate -l` on request only (RecommendedUpdates plist is undocumented). HTTPS only, at most daily, never write into other apps' prefs. Latest (GPL) and Pearcleaner are learn-only. softwareupdate speed/side effects to confirm on John's Mac → ticket 017.
