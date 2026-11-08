# 006: Safety rules for TidyMyMac v1

**Status: decided (2026-11-07).** Settles ticket [006](../planning/tickets/006-safety-rule-format.md). Built on the v1 feature picks ([ticket 001](../planning/tickets/001-pick-v1-features.md)), research [003](../planning/research/003-open-source-cleaner-rules.md) and [004](../planning/research/004-feature-privilege-needs.md), the real-Mac checks ([008](../planning/research/008-mac-checks-results.md)) and the admin helper draft ([specs/005-admin-helper.md](005-admin-helper.md)).

John's choices: Pearcleaner stays learn-only; three risk levels. Everything else follows from decisions already in [map.md](../planning/map.md): Trash by default, caches and logs deleted permanently, every run logged, our own rule list with MIT/Apache reuse and credit.

---

## 1. Rule kinds

A safety rule (see [CONTEXT.md](../planning/CONTEXT.md)) says that a kind of item may be removed, and how.

| Kind | What it says | v1 features that use it |
|---|---|---|
| `clean` | Items matching these targets may be removed, under these conditions, in this way. | User and system caches, user and system logs, Xcode junk, AI junk, local AI models, iOS backups, installer leftovers, broken login items |
| `leftover-location` | When an app is removed or missing, look here for items named after its bundle ID, name or team ID. | Uninstaller, Leftover files |
| `protect` | Never touch anything matching this, whatever else says so. | Every removal in the app, including ones John picks by hand |
| `app-override` | Extra or excluded terms and paths for one app whose files don't follow the usual naming. | Uninstaller, Leftover files |

**Not rules.** These features remove things John picks by hand, so they have no rule list. They still pass the protected floor (section 5) and always use the Trash:
- Large and old files
- Duplicates
- Downloads review
- Duplicate downloads
- Disk Map

These are fixed operations, not rules: emptying the Trash bins, flush DNS, reindex Spotlight, thin Time Machine snapshots, and toggling login and background items. They live in the app or in the admin helper's allow-list (spec 005). A `clean` rule can name an operation by id, such as `simctl.deleteUnavailable`, but never contains a shell command.

## 2. File format and layout

Rules are **JSON files built into the app bundle**. The app reads them with Swift `Codable`, and they are checked against a JSON Schema kept in the repo.

```
Resources/Rules/
  caches.json              user + system caches
  logs.json                user + system logs
  developer.json           Xcode junk
  ai.json                  AI junk + local AI models
  backups.json             iOS device backups
  installers.json          installer leftovers
  launch-items.json        broken login items
  leftover-locations.json  where apps leave files
  app-overrides.json       per-app exceptions
  protected.json           additions to the protected floor
```

- Each file is `{ "schemaVersion": 1, "rules": [ ... ] }`.
- Unknown fields are a load error, so a typo can't silently drop a guard.
- JSON has no comments, so each rule has a `notes` field.
- The **rule-set version** is the app's build number. It is logged with every removal.

Why not the alternatives: rules written as Swift code mix with app code and are harder to review. YAML needs a third-party parser. CleanerML-style XML is GPL (we may only borrow ideas) and verbose.

## 3. Fields

### 3.1 `clean` rule

```json
{
  "id": "dev.xcode.derived-data",
  "title": "Xcode build data",
  "module": "cleanup",
  "category": "cache",
  "risk": "safe",
  "removes": "Intermediate build products and indexes for Xcode projects.",
  "keeps": "Your projects, archives and simulators.",
  "notes": "Xcode rebuilds this on the next build.",
  "targets": [
    { "root": "~/Library/Developer/Xcode/DerivedData", "match": "children" }
  ],
  "conditions": { "minAgeDays": 0, "minSizeBytes": 0 },
  "guards": { "appsNotRunning": ["com.apple.dt.Xcode"] },
  "action": "delete",
  "privilege": "user",
  "needsFullDiskAccess": false,
  "macOS": { "min": "14.0" },
  "status": "experimental",
  "source": {
    "origin": "cleardisk",
    "license": "MIT",
    "ref": "bysiber/cleardisk Sources/ClearDisk/DiskMonitor.swift @ <commit>",
    "changes": "Risk and wording rewritten; guard added."
  },
  "evidence": ["<Apple doc or observation note>"],
  "reviewed": "2026-11-07"
}
```

| Field | Values | Rules |
|---|---|---|
| `id` | Stable dotted id | Required, unique across all files, never reused. Logged with each removal. |
| `title`, `removes`, `keeps`, `notes` | Plain-English text shown in the review screen | `removes` and `keeps` are required. |
| `module` | `cleanup`, `applications`, `clutter`, `performance` | Which sidebar module shows it. |
| `category` | `cache`, `log`, `developer`, `ai-model`, `backup`, `installer`, `launch-item` | Drives the delete-vs-Trash check (section 4). Xcode build caches use `cache`; Xcode archives use `developer`. |
| `risk` | `safe`, `caution`, `risky` | Section 4. |
| `targets` | List of `{ root, match, pattern?, types?, maxDepth?, kind? }` | Section 3.2. |
| `conditions` | `minAgeDays`, `minSizeBytes`, `excludeNames` (globs), `owner` (`currentUser` or `root`), `launchProgramMissing` (bool) | Age is the newest modification date found while sizing the item. `launchProgramMissing` is used for broken login items: the plist's `Program` or `ProgramArguments[0]` does not exist. |
| `guards` | `appsNotRunning` (bundle IDs), `processesNotRunning` (names), `skipIfOwnerAppRunning` (bool), `onlyIfAppMissing` (bundle ID) | If a guard can't be checked, the item is skipped. `skipIfOwnerAppRunning` is checked at removal, not at scan: an item belongs to an open app when its name is the app's bundle ID (or starts with it), the app's or executable's name, or the vendor part of the bundle ID of an app with a Dock icon (`Google` → `com.google.Chrome`). Before a clean the app offers to quit those apps (Quit, Quit All, Ignore); items of apps still open are skipped. |
| `action` | `delete`, `trash`, `operation` (+ `operationId`) | Section 4. |
| `privilege` | `user` or `helper` (+ `zone`) | A `helper` rule names one zone from spec 005 §5, and its targets must lie inside that zone. The helper re-checks everything, so the rule can only narrow what the zone allows. |
| `needsFullDiskAccess` | bool | Without FDA, the rule shows greyed out with a link to FDA onboarding. It is never half-run. |
| `macOS` | `min`, optional `max` | Lets paths that move between releases be retired. |
| `status` | `experimental` or `verified` | Section 6. |
| `source` | `origin`, `license`, `ref`, `changes` | Required. Section 7. |
| `evidence` | Links or notes | Why it's safe to remove. Required when `risk` is `safe`. |
| `reviewed` | Date | Last human review. |

### 3.2 Targets

- `root` is an absolute path, or starts with `~`, `$TMPDIR` or `$DARWIN_USER_CACHE_DIR`.
- `match` is one of:
  - `self`: the root itself is one item, for example a models folder.
  - `children`: each direct child of the root is one item.
  - `glob`: `pattern` is matched one path component at a time below the root. `*` never crosses a `/`, and `**` is not allowed.
  - `types`: Spotlight content types under the root, for example `com.apple.disk-image` and `com.apple.installer-package-archive`.
- `maxDepth` defaults to 1 and can be at most 3.
- `kind` is `file`, `directory` or `any` (the default).

### 3.3 The other kinds

- **`leftover-location`:** `id`, `root`, `match` (`bundleId`, `appName` or `teamId`; a name matches when it contains the term, ignoring case), `maxDepth` (default 1), `privilege` (+ `zone`), `needsFullDiskAccess`, `action` (always `trash`), `source`, `reviewed`.
- **`protect`:** `id`, `root`, `match` (`self`, `children` or `glob`), `reason`, `source`. A protect entry blocks the matched item and everything inside it.
- **`app-override`:** `bundleId`, `extraTerms`, `excludeTerms`, `extraPaths`, `excludePaths` and `sharedWith`. `sharedWith` lists other bundle IDs that use the same files, so removing one app of a suite never takes files the others still use. Overrides are written from our own observation of each app. Pearcleaner's and PureMac's condition lists are not copied (section 7).

## 4. Delete or Trash, and risk levels

**Delete or Trash (enforced by the linter):**
- `action: delete` is allowed only for `category` `cache` or `log`. Every other category uses `trash` or an `operation`.
- `risky` rules can never use `delete`.
- `helper` rules use their zone's action from spec 005: `systemCaches`, `systemLogs` and `rotatedLogs` delete. `launchItems`, `libraryLeftovers` and `rootApps` move items to John's Trash, with the helper's restore ledger.
- Emptying the Trash bins is its own operation, because it is permanent by definition. Listing and sizing `~/.Trash` needs Full Disk Access (ticket 008).

**Risk levels (John's choice: three):**

| Risk | Meaning | In a scan | In Tidy Up |
|---|---|---|---|
| `safe` | The OS or the app recreates it, and it holds no user data. `evidence` is required. | Ticked | Included, ticked |
| `caution` | It can be recreated, but at a cost (re-downloads, rebuilds), or it holds a little state. | Shown, unticked | Shown, unticked |
| `risky` | It may be the only copy of something. | Shown, unticked, with a warning; each item must be ticked on its own (no "select all") | Never included |

The features John marked "review only" (iOS backups, local AI models) are `risky`. Their items can still be moved to the Trash one by one from their module.

## 5. Checks built into the engine

These checks are in code, not in rule files, so a bad rule file can't turn them off:

1. **Protected floor.** No rule file can override this list:
   - System folders: `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`, `/Library/Extensions`, `/.DocumentRevisions-V100`, `/.Spotlight-V100`.
   - Folders that are never removed as a whole: `/Applications` itself, and `~` itself.
   - Personal folders: `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`. Large and old files, duplicates and Disk Map may still trash items *inside* them that John picks by hand.
   - iCloud and cloud sync: `~/Library/Mobile Documents`, `~/Library/CloudStorage`.
   - `~/Library/Keychains`.
   - Photos and Music libraries, and anything inside any bundle or package.
   - `~/Library/Mail`.
   - TidyMyMac's own support, log and run-log files.

   `protected.json` can add to this list but never remove from it. It also carries the names the helper's `libraryLeftovers` deny list still needs (spec 005 §5.1): `Apple`, `Developer`, `CrashReporter`, `iPod`, `Script Editor`, `Audio`, `ColorSync`, `Fonts`, `Keyboard Layouts`, `Input Methods`, plus anything else the gap check against Mole turns up.
2. **No `com.apple.` leftovers.** Leftover matching never offers an item whose name starts with `com.apple.`, and never matches against Apple-signed apps.
3. **Path containment.** Symlinks and firmlinks are resolved, and the item must still be inside its rule's root. Symlinks are never followed, `..` is rejected, the root itself is never acted on, and nothing crosses onto another volume. Permanent deletes use the same descriptor-based walk as the helper (`SafetyFloor.SafeRemoval`): the parent is opened without following links, the item must still have the reviewed device and inode, and the tree is removed relative to descriptors, so a folder swapped for a symlink after review is never followed. A rule root whose path passes through a symlink inside the home folder is skipped and logged, not followed (system links such as `/tmp` and `/var` are tolerated). A folder that contains a media library (`.photoslibrary` and the like) is never removed either, not only the library itself; the helper refuses it too.
4. **Fresh check before removal.** Guards, conditions and the floor are checked again right before each item is removed, since the scan may be minutes old.
5. **Sizes.** Reported sizes are allocated size, so APFS clones and hard links aren't counted as space to free.
6. **Dry run.** Every rule can run report-only, listing exactly what it would remove and how.
7. **Run log.** Each removal records time, run ID, rule `id` (or `manual` for hand-picked items), rule-set version, path, allocated size, action (`trash`, `delete` or the operation id) and the result. The file format of the run log is left to the handoff.

## 6. The first rule set, and how rules are reviewed

**Where the rules come from.** For each v1 feature, rules are written from Apple's docs first. Gaps are then filled from the permissive sources in research 003, and the result is checked against Mole by reading it only. The seed list is below. Exact paths are confirmed by a dry run on John's Mac.

| Rule (id) | Targets | Category / risk / action | Priv. | FDA | Seed from |
|---|---|---|---|---|---|
| `cache.user.apps` | `~/Library/Caches`, children; skip if owner app running; excludes filled in during seeding | cache / safe / delete | user | no | own, mac-cleanup-py, PureMac |
| `cache.user.containers` | `~/Library/Containers/*/Data/Library/Caches`, children | cache / safe / delete | user | yes | own, PureMac |
| `cache.system` | `/Library/Caches`, children | cache / caution / delete | helper `systemCaches` | no | own |
| `log.user` | `~/Library/Logs`, children (includes DiagnosticReports) | log / safe / delete | user | no | own, mac-cleanup-py |
| `log.system` | `/Library/Logs`, children | log / safe / delete | helper `systemLogs` | no | own |
| `log.system.rotated` | `/private/var/log`, rotated archives | log / safe / delete | helper `rotatedLogs` | no | own |
| `dev.xcode.derived-data` | `~/Library/Developer/Xcode/DerivedData`, children; Xcode not running | cache / safe / delete | user | no | ClearDisk |
| `dev.xcode.previews` | `~/Library/Developer/Xcode/UserData/Previews` | cache / caution / delete | user | no | ClearDisk |
| `dev.xcode.device-support` | `~/Library/Developer/Xcode/* DeviceSupport`, children | cache / caution / delete | user | no | ClearDisk |
| `dev.xcode.archives` | `~/Library/Developer/Xcode/Archives`, children | developer / risky / trash | user | no | ClearDisk |
| `dev.simulators.unavailable` | operation `simctl.deleteUnavailable`; Xcode and Simulator not running | developer / caution / operation | user | no | own, mac-cleanup-py |
| `ai.caches` | caches of AI apps and tools, filled from PureMac's AI Apps category | cache / caution / delete | user | no | PureMac |
| `ai.models.ollama` | `~/.ollama/models` (one item) | ai-model / risky / trash | user | no | own |
| `ai.models.lmstudio` | `~/.lmstudio/models` (one item) | ai-model / risky / trash | user | no | own |
| `ai.models.huggingface` | `~/.cache/huggingface/hub`, children | ai-model / risky / trash | user | no | own |
| `backup.ios` | `~/Library/Application Support/MobileSync/Backup`, children | backup / risky / trash | user | yes | own |
| `installer.leftovers` | `~/Downloads` and `~/Desktop`, types `com.apple.disk-image`, `com.apple.installer-package-archive`, depth 2 | installer / caution / trash | user | no | own |
| `launch.user.broken` | `~/Library/LaunchAgents/*.plist` with program missing | launch-item / caution / trash (after `launchctl bootout`) | user | no | own |
| `launch.system.broken` | `/Library/LaunchAgents`, `/Library/LaunchDaemons`, program missing | launch-item / caution / trash | helper `launchItems` | no | own |

The leftover locations are seeded from app-cleaner.sh's list of about 27 places (MIT):
- **User folders:** under `~/Library`, including Application Scripts, Application Support, Caches, Containers, Group Containers, HTTPStorages, LaunchAgents, Logs, Preferences, Preferences/ByHost, Saved Application State and WebKit. These run with user privilege, and Containers and Group Containers need FDA.
- **System folders:** their `/Library` equivalents, through the helper's `libraryLeftovers` and `launchItems` zones.
- **Package receipts:** checked with `pkgutil`.

**How a rule gets reviewed before it ships:**

1. **Automated lint**, run with the tests. It checks:
   - the schema is valid and ids are unique;
   - the licence is on the allowed list;
   - `delete` is used only for caches and logs, and `risky` never deletes;
   - every `safe` rule has evidence;
   - no target overlaps the protected floor;
   - every `helper` target lies inside its zone, with the zone's action.
2. **Fixture tests.** Each rule gets at least one fake folder tree it must match and one it must not. The trees include a symlink escape, a protected path and an item inside a bundle.
3. **Real-Mac dry run.** New or changed rules ship as `experimental`, and their items always show unticked, whatever their risk. After a dry run on John's Mac looks right, the rule becomes `verified` with a new `reviewed` date.
4. **John's review.** Rule changes go through a pull request John approves, once there is a repo.

**Updates.** Rules change only with a new signed build. v1 never downloads rules, because a tampered rule file amounts to a "delete this path" command. John's own **ignore list**, kept in the app's support folder by path or rule id, can only narrow what the rules do.

## 7. Credit and licences

- `source.license` must be `own`, `MIT` or `Apache-2.0`. Mole and BleachBit (GPL) and Pearcleaner (Apache 2.0 plus Commons Clause) are learn-only, so the linter rejects them (John, 2026-11-07).
- Don't copy PureMac's `Conditions.swift` or `Locations.swift`, because they appear to be derived from Pearcleaner. Its categories and scan paths are fine to use.
- The app ships a `CREDITS.md` listing each source project, its URL, the commit used, its licence and what we took. The full licence texts go in `ThirdPartyLicenses/`.
- For mac-cleanup-py (Apache-2.0), keep its licence text and note that we changed the paths (Apache §4(b)). It has no NOTICE file to carry.

## 8. Left to other tickets

- Which items Tidy Up includes, and how the review screen looks: Tidy Up flow, ticket 007.
- The end-to-end test plan beyond rule fixtures: the "Testing and safety" topic on the map.
- The run log's file format: handoff.
- The helper's zones and deny list: spec 005. This spec supplies the extra deny names in §5.1.
