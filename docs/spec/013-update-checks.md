# Spec 013: App and macOS update checks (check only)

Ticket: [013](../planning/tickets/013-app-update-checks.md). Findings and sources: [research/013](../planning/research/013-app-update-checks.md). Written for ticket 018 from the research recommendation, which the map already records as decided. Code lives in `AppInventory` (spec 016 §3). Screen: Applications › Updates (spec 007 §2, §4).

**TidyMyMac never installs, downloads or launches an updater.** It tells John what is out of date and opens the app (or Software Update) so the app updates itself.

## 1. Which apps

Every `.app` directly in `/Applications`, one vendor-folder level below it, and `~/Applications`. Apple-signed apps (`anchor apple`) are skipped; macOS covers them (§5).

## 2. Finding the update source, in this order

| # | Check | Result |
|---|---|---|
| 1 | `Contents/_MASReceipt/receipt` exists | **App Store**: row says "Updated by the App Store", button opens the App Store app. No version check. |
| 2 | Info.plist `SUFeedURL` (trim surrounding quotes and whitespace) | **Sparkle feed** |
| 3 | `Contents/Resources/app-update.yml` with provider `generic` or `s3` | **Electron feed**: `<url>/latest-mac.yml` |
| 4 | Homebrew cask catalogue, matched by bundle ID, then by app file name | **Homebrew** version |
| 5 | none of the above | **No update source** (shown honestly in a collapsed "Not checked" group) |

Skipped in v1: `SUFeedURL` in the app's user defaults, DevMate feeds, GitHub-provider electron feeds (they fall to Homebrew).

Homebrew catalogue: `https://formulae.brew.sh/api/cask.json`, cached in `~/Library/Application Support/TidyMyMac/Cache/cask.json`, refreshed at most once a week. Only `token`, `version`, `artifacts` app names and bundle IDs (from `uninstall`/`zap` `quit`/`launchctl` entries where present) are kept. The parsing logic follows Homebrew's livecheck `Sparkle`/`ElectronBuilder` strategies (BSD-2-Clause, credited in `CREDITS.md`).

## 3. Reading a feed

- Sparkle appcast: `XMLParser` with `shouldProcessNamespaces = true`; match the Sparkle namespace URI `http://www.andymatuschak.org/xml-namespaces/sparkle`, not the prefix. Tolerate a trailing `<!-- sparkle-signatures: … -->` block. Signature verification is **not** in v1.
- Per item: `sparkle:version` (enclosure attribute, then element; filename fallback not used), `sparkle:shortVersionString` (same order), `title`, `pubDate`, `link`, `sparkle:releaseNotesLink`, and the filter fields.
- Filters (mirror Sparkle): `sparkle:os` macOS only; no delta items; default channel only (drop any item with `sparkle:channel`); `minimumUpdateVersion` must pass; `minimumSystemVersion`/`maximumSystemVersion` against `ProcessInfo.operatingSystemVersion`; `hardwareRequirements` arm64 is fine. Phased rollout ignored.
- Best item = highest `sparkle:version` under the comparator; ties keep the first in the feed. Never trust feed order.
- Electron `latest-mac.yml`: read top-level `version`; compare with `CFBundleShortVersionString`.

## 4. Comparing versions

- Port Sparkle's `SUStandardVersionComparator` verbatim (MIT, credited) with its unit tests (research 013 §3 table, including the known `.1` bug).
- Sparkle: compare `sparkle:version` with installed `CFBundleVersion`; display `shortVersionString` → `CFBundleShortVersionString`.
- Homebrew: cask `version` is `short` or `short,build`. Compare `build` with `CFBundleVersion` when present, else `short` with `CFBundleShortVersionString`.
- Update exists only when the result is `orderedDescending`. A per-app override list (`Rules/update-overrides.json`, bundle ID → ignore) handles apps with custom comparators that give false positives.

## 5. macOS updates

- On every Updates refresh: read `/Library/Preferences/com.apple.SoftwareUpdate.plist` (`RecommendedUpdates`, `LastRecommendedUpdatesAvailable`). Undocumented; if unreadable or malformed, show "Unknown".
- Button **Check Apple Updates**: `/usr/sbin/softwareupdate --list` via `Process` (absolute path, argument array, no shell), off the main thread, timeout **120 s** until the first-build timing check (spec 017 §7 item 5) sets it to 3 × slowest run, minimum 60 s. Parse `* Label:` and `Title:` lines. No root.
- Never `--install` or `--download`. Row button opens `x-apple.systempreferences:com.apple.Software-Update-Settings.extension` (verified at first build).

## 6. Network rules

- HTTPS only. `http://` feeds are not fetched; the row shows "Insecure feed, not checked". No ATS exceptions.
- User-Agent `TidyMyMac/<version> (update check)`. Never impersonate the app.
- At most 4 feeds at once, 15 s timeout each. Results cached in `Cache/updates.json`.
- Automatic check at most once per 24 h, when Applications › Updates or Smart Care opens; **Check Now** button forces it. Setting "Check for app updates automatically" (on by default).
- Never write into another app's preferences, never use `SPUUpdater` or `sparkle-cli` on other bundles.

## 7. Display

Row: icon, name, `current → available` (short versions), source badge (Sparkle / Electron / Homebrew / App Store), release-notes link when present, **Open App**. Health shows the count only (spec 012). Smart Care's Applications card links the count.
