# 013: Finding and comparing app update feeds (check-only updater)

Researched 2026-11-07 for TidyMyMac (native Swift, macOS 14+, Apple Silicon, outside the App Store). Answers ticket 013 for the check-only updater in ticket 001.

**Method.** Sparkle's source (`sparkle-project/Sparkle`, commit `14fdbf2`, version 2.10.1, MIT) and its documentation site (`sparkle-project/sparkle-project.github.io`, commit `6524f21`) were shallow-cloned and read. So were two open-source update checkers: Latest (`mangerlahn/Latest`, commit `1301cf6`) and Pearcleaner (`alienator88/Pearcleaner`, commit `7724df7`). `Homebrew/homebrew-cask` (commit `38b024c`, 2026-11-07) was cloned and grepped to measure feed coverage. Homebrew's livecheck strategies and electron-builder's docs were read from GitHub. No Mac was available, and the network blocked `formulae.brew.sh`, `itunes.apple.com` and most man-page mirrors, so the `softwareupdate` facts come from a transcription of the man page plus one Mac-admin write-up. Both are marked as such. CleanMyMac was not downloaded or inspected.

**Licence policy (as in 003).** MIT, BSD or Apache-2.0: OK to copy with credit. GPL: learn from only. Anything else is called out.

## Key findings

1. **Where the feed URL lives.** Sparkle reads `SUFeedURL` from the app's **user defaults first, then its Info.plist**. An app's delegate (`feedURLStringForUpdater:`) can override both at runtime, and that override cannot be seen from outside. Sparkle strips surrounding quotes from the value. A static scanner can see three places: Info.plist `SUFeedURL`, the app's preferences domain (`SUFeedURL`, possibly in the domain named by `SUDefaultsDomain`), and, for Electron apps, `Contents/Resources/app-update.yml`.
2. **Which version to compare.** Compare the appcast's **`sparkle:version` against the installed `CFBundleVersion`**. `sparkle:shortVersionString` and `CFBundleShortVersionString` are for display only. Sparkle's own `SUHost.version` reads `CFBundleVersion`, and its docs say `sparkle:version` is the machine-readable `CFBundleVersion`.
3. **How Sparkle compares versions.** `SUStandardVersionComparator` is a tokenizing comparator, about 200 lines of MIT-licensed code. Key rules: `1.0` equals `1.0.0`; `1.0b1` is less than `1.0`; **everything after the first `-` is ignored**; a number beats a letter; a separator beats a letter. Port it verbatim along with its unit tests. Some apps supply their own comparator through a delegate; that is invisible from outside, but rare.
4. **Choosing the newest item.** Mirror Sparkle's filters. Keep only items whose `sparkle:os` is macOS (the default). Drop delta items, items whose `minimumUpdateVersion` the installed version fails, items on non-default `sparkle:channel`s, items whose `minimumSystemVersion` or `maximumSystemVersion` excludes this Mac, and items that require arm64 on non-arm64 hardware. Of what remains, take the highest `sparkle:version`; when two are equal, the first one in the feed wins.
5. **macOS updates without root.** `softwareupdate --list` is the only command that needs no admin rights. It contacts Apple's catalog, so it takes seconds and is reported to sometimes hang `softwareupdated`. A cheaper passive option is to read `/Library/Preferences/com.apple.SoftwareUpdate.plist` (`RecommendedUpdates`, `LastRecommendedUpdatesAvailable`). That file is undocumented.
6. **How many apps have a feed.** In Homebrew's cask catalogue, **953 of 4,210 app casks (about 23%)** are version-checked through a Sparkle feed and **208 (about 5%)** through an electron-builder YAML feed. The remaining **about 70%** have no Sparkle or electron feed that a scanner can find. Homebrew tracks these through GitHub releases, vendor pages or headers. Apps with their own updaters (Google, Microsoft, JetBrains, Adobe and so on) fall in this group. App Store and Apple apps are not in the cask catalogue at all. This is a share of the catalogue, not of a typical Mac.
7. **Existing projects.** **Latest** is GPL-3.0 (learn from only). **Pearcleaner** is Apache-2.0 with the Commons Clause (no selling; fine for personal use, but treat as non-standard). Both drive `SPUUpdater` against *other* apps' bundles. That writes `SULastCheckTime` and `SUHasLaunchedBefore` into those apps' preferences. TidyMyMac should not do this. Homebrew's livecheck `Sparkle` and `ElectronBuilder` strategies are BSD-2-Clause, so the parsing logic can be copied with credit.

---

## 1. Finding an app's feed

### 1.1 Sparkle's own lookup order

`-[SPUUpdater retrieveFeedURL:]` (Sparkle/SPUUpdater.m, about lines 1072–1120):

1. It reads `[_host objectForKey:SUFeedURLKey]`. `SUHost -objectForKey:ofClass:` returns the **user-defaults value if present, otherwise the Info.plist value** (SUHost.m:417–420).
2. If the delegate implements `feedURLStringForUpdater:` and returns a non-nil value, that value wins.
3. It trims `"` and `'` from the string ("Some feed publishers add quotes; strip 'em"), then calls `URLWithString`.

Since 2.x, setting the feed in user defaults through `setFeedURL:` is deprecated. Sparkle logs a warning when it finds one (SPUUpdater.m:174–180). The docs recommend Info.plist `SUFeedURL`, plus channels for betas.

The user-defaults domain is the app's standard defaults, or the domain named by Info.plist `SUDefaultsDomain` if set (SUHost.m:75–90; customization docs).

### 1.2 What TidyMyMac can see, in order of yield

| Source | How | Notes |
|---|---|---|
| `Contents/Info.plist` → `SUFeedURL` | `Bundle(url:).infoDictionary` | Covers almost all Sparkle apps. Trim quotes. Latest and Pearcleaner do exactly this. |
| Preferences → `SUFeedURL` | `CFPreferencesCopyAppValue("SUFeedURL", bundleID)`, or the domain from `SUDefaultsDomain` | Rare and deprecated. Sandboxed apps keep preferences in `~/Library/Containers/<id>/…`, which needs FDA or triggers a prompt on macOS 14 (see 004). Optional. |
| Sparkle present but no `SUFeedURL` | `Contents/Frameworks/Sparkle.framework` exists | The feed is set in code, so it can't be found. Fall back to Homebrew (§5). |
| DevMate apps | `Contents/Frameworks/DevMateKit*` → `https://updates.devmate.com/<bundleID>.xml` | Latest and Pearcleaner both have this fallback. DevMate shut down years ago, so expect dead feeds. Low value. |
| Electron (electron-builder) | `Contents/Resources/app-update.yml` (provider and URL) → `latest-mac.yml` | electron-builder docs: "the first provider written to `app-update.yml` inside the packaged app" is the feed the installed app polls. Homebrew's `ElectronBuilder` strategy parses the YAML `version`. Generic and S3 providers give a URL; the GitHub provider means using GitHub Releases. |
| Mac App Store apps | `Contents/_MASReceipt/receipt` exists | No feed. Latest queries Apple's public iTunes lookup endpoint (`https://itunes.apple.com/lookup?bundleId=…`). For a check-only tool, "open the App Store" is enough (004 already rates the App Store as private API). |

Also read `SUPublicEDKey` from Info.plist if you want to verify signed feeds (§2.4).

## 2. Parsing the appcast

The appcast is RSS 2.0 with the Sparkle namespace `http://www.andymatuschak.org/xml-namespaces/sparkle`. Match on the **namespace URI, not the `sparkle:` prefix**. Sparkle 2.10.1 fixed a bug where "appcast child elements [were] ignored when the Sparkle namespace uses a custom prefix" (CHANGELOG, #2923). Use `XMLParser` with `shouldProcessNamespaces = true`.

### 2.1 Per `<item>` fields to read

Names are from SUConstants.m:59–99.

- **Version.** Read `sparkle:version` from the `<enclosure>` attribute first, then from the `<item>` element. As a last resort Sparkle takes the enclosure filename between the last `_` and the extension, and only for unsigned feeds (SUAppcastItem.m:465–500). The publishing docs now recommend the element form; both forms are valid.
- **Display version.** `sparkle:shortVersionString`: enclosure attribute, then element (SUAppcastItem.m:737–740).
- **Release info.** `title`, `pubDate`, `link`, `sparkle:releaseNotesLink`, `sparkle:fullReleaseNotesLink`, `description`.
- **Filters.** `sparkle:os` (default `macos`), `sparkle:channel`, `sparkle:minimumSystemVersion` and `sparkle:maximumSystemVersion` (three-part version), `sparkle:hardwareRequirements` (`arm64`, Sparkle 2.9+), `sparkle:minimumUpdateVersion`, `sparkle:minimumAutoupdateVersion` (marks a "major upgrade"), `sparkle:criticalUpdate`, `sparkle:informationalUpdate`, and `sparkle:phasedRolloutInterval`.
- An item with no `<enclosure>` and only `<link>` plus `sparkle:version` is a valid "download from website" update (publishing docs).

### 2.2 Selection logic

From SUAppcastDriver.m:500–575.

1. `filterAppcast:forMacOSAndAllowedChannels:` drops non-macOS items, delta items, items failing `minimumUpdateVersionIsOK`, and items on any channel other than the default. An app can opt into other channels only through a delegate, which you can't see, so **use the default channel only**.
2. `filterSupportedAppcast:` drops items whose min/max OS version or arm64 requirement fails. It also applies phased rollout, but only for background checks, and that depends on the app's random `SUUpdateGroupIdentifier`. **A check-only tool should ignore phased rollout.** At worst it reports an update a few days before the app itself offers it. Optionally mark items whose `pubDate + 6 × interval` is still in the future as "rolling out".
3. `bestItemFromAppcastItems:` keeps the item with the highest `versionString` under the comparator; when two are equal, the first wins. **Do not assume the feed is sorted.**
4. An update exists if `compare(best.version, installed CFBundleVersion) == .orderedDescending`.

### 2.3 CFBundleVersion vs CFBundleShortVersionString

- `SUHost.version` reads `kCFBundleVersionKey`. `displayVersion` reads `CFBundleShortVersionString` and falls back to `CFBundleVersion` (SUHost.m:170–193).
- Publishing docs: "the internal version number (`CFBundleVersion` and `sparkle:version`) is intended to be machine-readable". `sparkle:shortVersionString` is what users see.
- So compare `sparkle:version` with `CFBundleVersion`, and show `shortVersionString` / `CFBundleShortVersionString`.
- Latest instead compares build numbers only when they differ from the version number, otherwise version numbers (Latest/Model/Version/Version.swift:66–80). Pearcleaner uses `String.compare(_, options: .numeric)`. Both are approximations. Sparkle's rule above is what the apps themselves use.

### 2.4 Signed feeds (optional)

Since Sparkle 2.9, apps with `SURequireSignedFeed = YES` sign the appcast. The signature is a trailing comment block that starts `<!-- sparkle-signatures:\n` and has `edSignature: <base64>` and `length: <n>` lines. The signed content is everything before that block (SPUExtractSignedFeed.m). A check-only tool can verify it with the app's `SUPublicEDKey` using CryptoKit `Curve25519.Signing.PublicKey`. Without verification, the worst case is a spoofed "update available" message, so this is optional. The XML parser must tolerate the trailing comment; any standard parser does.

### 2.5 Network etiquette

- Sparkle's User-Agent is `<AppName>/<version> Sparkle/<sparkleVersion>` (SPUUserAgent+Private.m:22). sparkle-cli asks automated tools to set a recognisable name (`--user-agent-name`). Send something like `TidyMyMac/1.0 (update check)`. Don't impersonate the app.
- Some old feeds are `http://`. App Transport Security blocks those unless TidyMyMac's Info.plist allows them (Sparkle ATS docs). Either skip those feeds and report "insecure feed", or add a narrowly scoped exception.
- Cache the results, and check at most daily, with a manual "Check now".

## 3. Sparkle's version comparator

Source: Sparkle/SUStandardVersionComparator.m. The header says it was "adapted from MacPAD… 'dumb' in that it does essentially string comparison, in components split by character type." Algorithm:

1. **Split** the string into runs of the same character type. The types are number (decimal digits), string, period, other punctuation, and whitespace. Each separator character is its own part. **Splitting stops at the first `-`**, so `1.5.5-335d3e2` equals `1.5.5-a655360`.
2. **Balance** the leading number and period parts by padding the shorter side with `.` and `0`, so `1.0` equals `1.0.0` and `1.5b1` equals `1.5.0b1`.
3. **Compare part by part.** Numbers compare as `long long`. Strings compare with `compare:` (case-sensitive, literal). All separators are treated as equal. On a type mismatch, a non-string beats a string, and a number beats a period.
4. **When one side runs out.** If the next part of the longer side is a string, the **shorter side is newer** (`1.0b` < `1.0`). Otherwise the longer side is newer (`0.1` < `0.1.2`).

Test cases to port (Tests/SUVersionComparisonTest.m):

| a | b | result |
|---|---|---|
| `1.0` | `1.0.0` | equal |
| `0.1` | `0.0.1` | a > b |
| `1.0b1` | `1.0` | a < b |
| `1.0rc` | `1.0` | a < b |
| `1.0b9` | `1.0b10` | a < b |
| `1.0a1` | `1.0b1` | a < b |
| `0.9` | `1.0a1` | a < b |
| `1.0 (1234)` | `1.0 (1235)` | a < b |
| `3.3 (5847)` | `3.3.1b1 (5902)` | a < b |
| `1.5.5-335d3e2` | `1.5.6-b252311` | a < b |
| `201210251627` | `201211051041` | a < b |

There is a known bug: `.1` vs `0.0.1` is wrong. Leave it as is.

**Caveat.** An app can install its own comparator through `versionComparatorForUpdater:`. We can't see that. If it gives a false "update available" result for a particular app, add a per-app override in TidyMyMac's data.

**Licence.** MIT. Keep the copyright notice from Sparkle's LICENSE in TidyMyMac's acknowledgements.

## 4. macOS updates without root

**Command.** `softwareupdate --list` (`-l`). The `softwareupdate(8)` man page says the tool "requires admin authentication for all commands except --list". Listing marks recommended items with `*`. The `--help` output also documents `--no-scan` ("use previously scanned updates") and `--product-types` (e.g. `macOS`). (Man page transcription at sudo.is and dssw.co.uk; the footer date is old, so check the flags with `softwareupdate --help` on the target Mac.)

**Speed and side effects.** These come from a secondary source, a Mac-admin write-up by Graham Pugh:

- `--list` polls Apple's software catalogs, "which normally takes a few seconds".
- Admins report it can **hang `softwareupdated`**. The `launchctl kickstart` workaround reportedly stopped working in macOS 14.4.
- Its output can differ from what System Settings shows.
- When "Check for updates" is on, the system already checks in the background about every 6 hours.

No Apple-documented timing exists. **Measure on the real Mac** (ticket 008): `time softwareupdate -l`, run twice, plus `time softwareupdate -l --no-scan`.

**Passive alternative.** Read `/Library/Preferences/com.apple.SoftwareUpdate.plist`:

- `RecommendedUpdates` (array; empty when there are none) and `LastRecommendedUpdatesAvailable` (count).
- The result is instant, triggers no scan, and the same write-up says it matches the Settings pane more closely.
- It is undocumented, and how fresh it is depends on the background check.
- It is in `/Library/Preferences`, so it should be readable without root. Verify on 008.

**Suggested approach.**

1. Read the plist on every TidyMyMac refresh.
2. Offer a user-initiated "Check Apple updates" button that runs `/usr/sbin/softwareupdate --list` through `Process` with a timeout (e.g. 120 s). Run it off the main thread and parse the `* Label:` / `Title:` lines.
3. Never run `--install` or `--download`; installing is System Settings' job.
4. Deep-link to System Settings with `x-apple.systempreferences:com.apple.Software-Update-Settings.extension`. That link is unverified; confirm it on 008.

## 5. How many apps have no feed

**Data.** A Homebrew cask catalogue snapshot (commit `38b024c`, 2026-11-07, 7,818 casks), counted by grepping the cask files:

| Metric | Count | Share of app casks |
|---|---|---|
| Casks with an `app "…"` artifact | 4,210 | 100% |
| …that livecheck through `strategy :sparkle` | 953 | 22.6% |
| Casks of any kind with `strategy :electron_builder` | 208 | ~5% |
| Casks of any kind with `strategy :github_latest`/`:github_releases` | 932 | n/a |
| App casks with no `livecheck` block (default URL/page heuristics) | 755 | 17.9% |
| Sparkle-strategy casks also marked `auto_updates true` | 872 of 1,004 | n/a |

**Reading the numbers.**

- About **one in four or five third-party apps** exposes a Sparkle feed that a scanner can find. Add about 5% for electron-builder YAML feeds.
- On a real Mac the share is lower, because Apple's own apps and App Store apps (which have no feed) make up a large part of `/Applications`.
- The undercount goes both ways. Some Sparkle apps' casks use other strategies, and some Sparkle apps set the feed in code.
- For the roughly 70% without a feed, the usable fallback is **Homebrew's cask JSON API** (`https://formulae.brew.sh/api/cask.json`). Match on bundle ID, taken from the `uninstall`/`zap` paths, or on app name from the `app` artifacts. This is what Latest does (UpdateRepository.swift, `UpdateRepository+Entry.swift`). Cask `version` is often `short,build`, so split on `,`. The JSON is a large download (several MB); cache it for a day.

**Measure the real number on the user's Mac** by adding this to 008-mac-checks.sh:

```sh
for a in /Applications/*.app; do p="$a/Contents/Info.plist"
  if [ -d "$a/Contents/_MASReceipt" ]; then echo MAS
  elif /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$p" >/dev/null 2>&1; then echo SPARKLE_FEED
  elif [ -d "$a/Contents/Frameworks/Sparkle.framework" ]; then echo SPARKLE_NOFEED
  elif [ -f "$a/Contents/Resources/app-update.yml" ]; then echo ELECTRON_YML
  elif /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$p" 2>/dev/null | grep -q '^com\.apple\.'; then echo APPLE
  else echo NONE; fi; done | sort | uniq -c
```

## 6. Existing open-source projects

| Project | Licence (from repo) | What it does | Reuse |
|---|---|---|---|
| **Sparkle** (`sparkle-project/Sparkle`) | MIT (LICENSE; some bundled parts list their own licences under "EXTERNAL LICENSES") | Owns the format, the comparator and the filtering rules. Also ships `sparkle-cli bundle --probe`, which checks another bundle without installing: exit 0 means an update is available, `--feed-url` and `--channels` are supported. | Port `SUStandardVersionComparator` and the filtering rules with credit. Don't drive `SPUUpdater` or `sparkle-cli` against other apps (see below). |
| **Latest** (`mangerlahn/Latest`) | **GPL-3.0** (LICENSE.md) | Sparkle apps (Info.plist `SUFeedURL` + DevMate fallback → `SPUUpdater` with a custom `SPUUserDriver`), App Store apps (iTunes lookup), everything else through the Homebrew cask API. | **Learn only.** Good reference for the three-source design and the cask matching. |
| **Pearcleaner** (`alienator88/Pearcleaner`) | **Apache-2.0 + Commons Clause** (LICENSE.md) | "Apps Updater": `SparkleUpdateChecker.swift` (Info.plist only, DevMate fallback, `SPUUpdater` with a custom driver and `bestValidUpdate`), Homebrew and App Store checkers. The App Store side uses private frameworks. | Personal use is permitted; selling is not. Treat as reference. |
| **Homebrew livecheck** (`Homebrew/brew`, `livecheck/strategy/sparkle.rb`, `electron_builder.rb`) | BSD-2-Clause | Parses appcasts: enclosure attributes first, then elements, `channel`, `minimumSystemVersion`. Also parses electron-builder YAML. | Copy logic with credit. Mainly useful as a cross-check of field handling. |

**Why not drive `SPUUpdater` against other apps, as Latest and Pearcleaner do?**

- For a non-main bundle, `SUHost` uses `NSUserDefaults(suiteName: <thatBundleID>)` (SUHost.m:75–90). Starting and checking then **writes into the other app's preferences**: `SUHasLaunchedBefore` (SPUUpdater.m:419) and `SULastCheckTime` (SPUUpdater.m:497). That can shift that app's own check schedule.
- It drags in the whole framework, plus its XPC and installer pieces, for a check-only feature.
- It still can't see the app's delegate (custom feed, channels, comparator), so it gains nothing over a small parser.
- `start` can also refuse apps whose key setup is invalid (SPUUpdater.m:316–380).

---

## Recommendation

Build a small, dependency-free `UpdateFeeds` module in Swift. Do not embed Sparkle.

1. **Discovery, per app in `/Applications` and `~/Applications`.** Classify each app in this order:
   - App Store app (`_MASReceipt`): report "App Store" and link to the App Store.
   - Info.plist `SUFeedURL` (quotes trimmed): Sparkle feed.
   - `Contents/Resources/app-update.yml` with a generic or S3 URL: electron feed (`latest-mac.yml`).
   - Otherwise: look the app up in a cached Homebrew `cask.json`, matched by bundle ID, then by app name.
   - Otherwise: "No update source". Show it honestly; don't guess.
   - Skip the user-defaults `SUFeedURL` and DevMate paths in v1.
2. **Parsing.** Namespace-aware `XMLParser`. Read version and shortVersion from the enclosure attribute, then the element. Apply Sparkle's filters: macOS only, no deltas, default channel only, `minimumUpdateVersion`, min/max system version against `ProcessInfo.operatingSystemVersion`, arm64 hardware requirement. Ignore phased rollout. Pick the maximum `sparkle:version`; don't trust the feed order.
3. **Comparison.** Port `SUStandardVersionComparator` verbatim (MIT, credited) with its unit tests. Compare `sparkle:version` with `CFBundleVersion`, and show the short versions. For Homebrew results, compare the cask's `short,build` against `CFBundleShortVersionString` and `CFBundleVersion` with the same comparator.
4. **macOS updates.** Read `/Library/Preferences/com.apple.SoftwareUpdate.plist` passively. Offer a user-triggered, timed-out `softwareupdate --list` with no root, and never install. Confirm plist readability, the `-l` timing and the Settings deep link on the real Mac (add these to ticket 008, with the coverage script in §5).
5. **Etiquette and safety.** Use HTTPS only, and report `http://` feeds as insecure instead of adding an ATS exception. Send an honest User-Agent, check at most daily, run a few checks concurrently (e.g. 4–6) with a 15 s timeout each, and verify signed feeds with `SUPublicEDKey` later if wanted. Never write into other apps' preferences, which rules out `SPUUpdater` and `sparkle-cli` on foreign bundles.

Expected coverage: about 25–30% of third-party apps from feeds directly, more with the Homebrew fallback. Apple and App Store apps go through the App Store and Software Update instead.

## Sources

- Sparkle source, commit `14fdbf2` (2.10.1): `Sparkle/SPUUpdater.m` (`retrieveFeedURL:`, start-up key checks, user-defaults writes), `Sparkle/SUHost.m`, `Sparkle/SUConstants.m`, `Sparkle/SUAppcastItem.m`, `Sparkle/SUAppcastDriver.m`, `Sparkle/SUStandardVersionComparator.{h,m}`, `Sparkle/SPUExtractSignedFeed.m`, `Sparkle/SPUUserAgent+Private.m`, `Tests/SUVersionComparisonTest.m`, `sparkle-cli/main.m`, `CHANGELOG`, `LICENSE` — https://github.com/sparkle-project/Sparkle
- Sparkle documentation (site repo commit `6524f21`): Publishing (`documentation/publishing`), Customization (`documentation/customization`), sparkle-cli (`documentation/sparkle-cli`), App Transport Security (`documentation/app-transport-security`) — https://sparkle-project.org/documentation/
- Latest, commit `1301cf6`, GPL-3.0: `Latest/Model/Sparkle/Sparkle.swift`, `Update Checker Extensions/Sparkle/SparkleCheckerOperation.swift`, `Model/Version/Version.swift`, `Update Repository/UpdateRepository.swift`, `UpdateRepository+Entry.swift`, `App Store/MacAppStoreCheckerOperation.swift`, `LICENSE.md` — https://github.com/mangerlahn/Latest
- Pearcleaner, commit `7724df7`, Apache-2.0 + Commons Clause: `Pearcleaner/Logic/AppsUpdater/SparkleUpdateChecker.swift`, `LICENSE.md`, `README.md` — https://github.com/alienator88/Pearcleaner
- Homebrew/homebrew-cask, commit `38b024c` (2026-11-07), `Casks/**` grep counts — https://github.com/Homebrew/homebrew-cask
- Homebrew/brew `Library/Homebrew/livecheck/strategy/sparkle.rb`, `electron_builder.rb`, `LICENSE.txt` (BSD-2-Clause) — https://github.com/Homebrew/brew
- electron-builder `website/docs/publish.md` (`app-update.yml` feed) and LICENSE (MIT) — https://github.com/electron-userland/electron-builder
- `softwareupdate(8)` man page, as transcribed at https://sudo.is/docs/macos/man_softwareupdate.html and https://dssw.co.uk/reference/softwareupdate/ (mirrors; Apple no longer hosts the page)
- Secondary: Graham Pugh, "Do you need to use the softwareupdate command to discover available updates?" (2022, updated for 14.4) — https://grahamrpugh.com/2022/09/29/software-update-check.html
- Cross-reference: `/mnt/project-files/tidymymac/wayfinder/research/004-feature-privilege-needs.md` (Updater rows; FDA for containers)
