# TidyMyMac admin helper: design spec

Ticket: [005 Design the admin helper](../planning/tickets/005-admin-helper-design.md). Status: **decided (2026-11-07)**.

**John's choices:** admin password once per cleanup run (§7); root-owned items go to John's Trash with restore from TidyMyMac (§8); app ID `io.github.joswalt.TidyMyMac` (§3).

Inputs: [research 002](../planning/research/002-helper-without-dev-account.md) (how to install it), [research 004](../planning/research/004-feature-privilege-needs.md) (which features need root), [ticket 001](../planning/tickets/001-pick-v1-features.md) (v1 feature picks), [ticket 008](../planning/research/008-mac-checks-results.md) (real-Mac permission checks), [spike 009 results](../planning/spike-009/RESULTS.md) (free signing proven on John's Mac, macOS 26.7.1), [spec 006](006-safety-rules.md) (safety rules and protected floor).

Scope: only the **v1 features that need root** (§5, §6). Features marked Later that would need the helper are listed in §13 so they can be added without redesign.

---

## 1. Summary

- One root helper, `TidyMyMacHelper`, embedded in the app bundle and registered with **`SMAppService.daemon`**. John approves it once in System Settings › General › Login Items.
- The app talks to it over **XPC**. Each side checks the other's code signature on every connection.
- The helper exposes a **short, typed list of operations** (§6). There is no "run command" and no "delete this path" operation.
- **The helper decides what may be touched, not the app.** Root-level files can only be acted on through *handles* that the helper itself issued while scanning one of its compiled-in **zones** (§5). The app can pick from the scan results and can never name a path of its own.
- Destructive operations require an **admin authentication**, cached for 5 minutes, so one cleanup run asks once (§7).
- Both targets are signed with John's free **Personal Team "Apple Development"** identity, with the hardened runtime on and no sandbox. Buying the $99 account later only swaps the identity and adds notarization (§9).

## 2. Goals and non-goals

**Goals**
1. A bug or compromise in the app cannot make the helper delete or change anything outside a fixed, reviewed set of places.
2. Nothing runs as root that does not need root. Everything in the user's home folder stays in the app.
3. A helper that is missing, unapproved or out of date never breaks the app. Root features show "Needs helper" and everything else still works.
4. The same design carries over unchanged to a notarized free download.

**Non-goals**
- No scheduled or background work by the helper. It only acts when the app asks.
- No GUI code in the helper (Apple: never run GUI code as root).
- None of the operations that research 004 marked harmful or obsolete (§6.4).

## 3. Names and bundle layout

Identifiers (one place to change them: `Config/Identity.xcconfig`):

| Item | Value |
|---|---|
| App bundle ID | `io.github.joswalt.TidyMyMac` |
| Helper identifier and launchd label | `io.github.joswalt.TidyMyMac.Helper` |
| Mach service name | `io.github.joswalt.TidyMyMac.Helper` |
| Authorization right | `io.github.joswalt.TidyMyMac.helper.modify` |
| Team ID | `26TUUFN7M2` (John's free Personal Team, from spike 009) |

`io.github.joswalt` is a reverse-DNS name John controls without buying a domain.

```
TidyMyMac.app/Contents/
  MacOS/TidyMyMac                      app
  MacOS/TidyMyMacHelper                helper (command-line tool target, Copy Files phase)
  Library/LaunchDaemons/io.github.joswalt.TidyMyMac.Helper.plist
```

The launchd plist:

```xml
<dict>
  <key>Label</key>                 <string>io.github.joswalt.TidyMyMac.Helper</string>
  <key>BundleProgram</key>         <string>Contents/MacOS/TidyMyMacHelper</string>
  <key>MachServices</key>          <dict><key>io.github.joswalt.TidyMyMac.Helper</key><true/></dict>
  <key>AssociatedBundleIdentifiers</key> <array><string>io.github.joswalt.TidyMyMac</string></array>
</dict>
```

No `RunAtLoad` and no `KeepAlive`. launchd starts the helper when the app connects, and the helper exits after **60 seconds** with no open connection and no running job. It costs nothing while idle.

Because `BundleProgram` points into the app bundle, updating the app updates the helper. The app must live in `/Applications`: Background Task Management records the bundle path, so a moved app looks like a missing helper. The app warns if it is run from anywhere else.

Proposed code layout (superseded by [spec 016](016-repo-layout.md)):

```
TidyMyMac/            SwiftUI app target
TidyMyMacHelper/      main.swift: XPC listener and wiring only
Packages/HelperProtocol/  shared Codable request and response types, protocol version
Packages/HelperCore/      zones, deny list, path validation, operations (unit tested, no XPC)
```

## 4. Install, approval and lifecycle

### 4.1 When the helper is installed

Not on first launch. The app registers the helper the first time John opens a feature that needs root, or presses **Install helper** in Settings › Helper. A sheet first explains, in plain words, the list of things the helper can do (generated from the operation table in §6, so it never drifts from the code).

### 4.2 States and what the app does

The app reads `SMAppService.daemon(plistName:).status` on launch, whenever it becomes active, and every 2 seconds while the install sheet is open.

| `status` | Meaning | App behaviour |
|---|---|---|
| `.notRegistered` | Never installed, or removed | Root features show **Needs helper** with an Install button |
| `.requiresApproval` | Registered, John has not allowed it yet | Show "Allow TidyMyMac in Login Items", button calls `SMAppService.openSystemSettingsLoginItems()` |
| `.enabled` | Approved | Connect and run the health check (§4.3) |
| `.notFound` | Bundle damaged, or the app was moved | Show **Repair helper** (§4.4) |

`register()` failing with `kSMErrorLaunchDeniedByUser` is treated as `.requiresApproval`, not as an error.

### 4.3 Health check and versions

Every new connection starts with `hello()`, which returns the helper's `protocolVersion`, build number and effective uid. The app requires `uid == 0`, an equal `protocolVersion` and an equal build number.

`status == .enabled` alone does not prove the helper runs: in spike 009 a badly signed build still showed `enabled` while launchd refused to start it. So `hello()` has a **5-second timeout**, and a timeout counts as a broken helper.

**After an app update or rebuild** (spike 009: the old helper process keeps answering until it is restarted):
1. The build number differs, so the app sends `shutdown()`, waits for the connection to drop, and reconnects. launchd starts the new binary.
2. If the build still differs, or `hello()` times out, the app does `unregister()` then `register()` silently. Spike 009 showed this loads the new binary with no re-approval and keeps Full Disk Access.
3. Only if that fails too, offer **Repair helper** (§4.4).

### 4.4 Repair and removal

- **Repair helper:** `unregister()`, then `register()`, then the approval flow again. If that still fails, the sheet shows the developer fallback for John: `sfltool resetbtm` and a restart (from research 002).
- **Remove helper** (Settings › Helper): `unregister()`. The app also tells John to do this before deleting TidyMyMac, since a stale Login Items entry can otherwise linger.

## 5. Zones: the only places the helper will touch

A **zone** is a fixed directory plus a fixed rule for which entries in it are items. Zones are compiled into the helper. The app cannot add, widen or change them. Every zone lists only **direct children** of its root: the helper never acts on the zone root itself, and never on something deeper than one level below it (a whole child folder can be removed, but the app cannot point inside one).

| Zone | Root(s) | Items | Allowed action | Features (feature list §) |
|---|---|---|---|---|
| `systemCaches` | `/Library/Caches` | each direct child | **delete** permanently | System cache files (2) |
| `systemLogs` | `/Library/Logs` | each direct child, except our own `TidyMyMac` folder | **delete** | System log files (2) |
| `rotatedLogs` | `/private/var/log` | files only, and only rotated archives: names ending `.gz`, `.bz2`, `.xz` or `.<number>` | **delete** | System log files (2) |
| `launchItems` | `/Library/LaunchAgents`, `/Library/LaunchDaemons` | `*.plist` files; the scan reports label, program path, whether the program exists, whether it is loaded and whether it is disabled | **trash**, after `launchctl bootout` | Broken login items (2), Background items (4), Uninstaller, Leftover files (5) |
| `libraryLeftovers` | `/Library/Application Support`, `/Library/Preferences`, `/Library/PrivilegedHelperTools`, `/Library/Caches` | each direct child | **trash** | Uninstaller, Leftover files (5) |
| `rootApps` | `/Applications` (and one subfolder level, for vendor folders) | `*.app` bundles the user cannot move to the Trash themselves (owned by root or another user) | **trash** | Uninstaller (5) |

`/Library/Caches` is in two zones on purpose: as a cache it is deleted (`systemCaches`), but when the Uninstaller removes one app's cache folder it goes to the Trash with the rest of that app (`libraryLeftovers`). The app picks the zone from the rule or feature that found the item (spec 006 §3, `privilege.zone`).

Ticket 008 found that moving a whole app to the Trash does not need the App Management permission (only changes *inside* another developer's bundle do), so `rootApps` needs no extra permission. Spike 009 found that the helper inherits TidyMyMac's Full Disk Access, so no zone needs a separate grant.

The **delete** vs **trash** choice belongs to the zone, not to the request. It follows the agreed rule: caches and logs are deleted, everything else goes to the Trash. The app cannot ask for a permanent delete in a trash zone.

### 5.1 Hard deny list (always refused)

Checked at scan time and again at action time, in `HelperCore`, independent of the safety rules from ticket 006:

- Anything whose name starts with `com.apple.` in `libraryLeftovers`, `launchItems` and `rootApps`.
- In `rootApps`: Apple-signed apps (`anchor apple` requirement), and TidyMyMac itself.
- In `libraryLeftovers`: `Apple`, `Developer`, `CrashReporter`, `iPod`, `Script Editor`, `Audio`, `ColorSync`, `Fonts`, `Keyboard Layouts`, `Input Methods` (the list from spec 006 §5), plus anything the rule gap check against Mole adds. The list is compiled into `HelperCore`; `protected.json` in the app carries the same names, and a unit test fails if the two differ.
- Our own files: `/Library/Logs/TidyMyMac`, `/Library/Application Support/TidyMyMac`.
- Any item with the `SF_RESTRICTED` (SIP), `SF_NOUNLINK`, `SF_IMMUTABLE` or `UF_IMMUTABLE` flag.
- Never anything under `/System`, `/usr` (except `/usr/local`, which is not a zone anyway), `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`, `/Library/Extensions`, or the unified log store. These match the protected floor in spec 006 §5, and `HelperCore` and the app share that floor as one Swift module so they cannot drift.

**How this fits with ticket 006:** the app's safety rules decide what to *suggest* (which caches are safe, what counts as a leftover of app X). The helper's zones and deny list are a floor underneath them: even a wrong rule, or a bug in leftover matching, cannot reach past them. Rules can only narrow what the helper allows, never widen it.

### 5.2 Handles

A scan returns, for each item, a **handle**: a random 128-bit ID. The helper keeps, per connection, a map from handle to `(zone, path, device, inode, scan time)`. The app also gets the display path, size on disk, modified date, owner and kind for the review screen.

Handles die when the connection closes or after **30 minutes**. An action with an unknown or expired handle is refused, and the app rescans.

### 5.3 Checks at action time

Before acting on a handle the helper:

1. Opens the zone root with `O_DIRECTORY | O_NOFOLLOW` and the item with `openat`/`fstatat(AT_SYMLINK_NOFOLLOW)` relative to it. No symlink is followed at any step, so swapping a folder for a symlink after the scan cannot redirect the action.
2. Requires the same device and inode as at scan time.
3. Re-applies the zone's item rule and the deny list.
4. For folders, deletes with `fts` using `FTS_PHYSICAL | FTS_XDEV` (never follows links, never crosses into another volume).
5. For **trash**, moves the item into the calling user's Trash (§8).

## 6. Operations (the allow-list)

The XPC interface is one `@objc` protocol. Requests and replies are `Codable` structs from `HelperProtocol`, sent as `Data`, so the Objective-C surface stays small. Every destructive operation takes a `dryRun` flag that runs all checks and reports what would happen, without changing anything.

### 6.1 Housekeeping (no authentication)

| Operation | Does |
|---|---|
| `hello()` | Returns protocol version, build, uid |
| `shutdown()` | Exits once the current job ends |
| `cancel(jobID)` | Stops a running job between items |

### 6.2 Read-only (no authentication)

| Operation | Does | Features |
|---|---|---|
| `scan(zone)` | Lists a zone's items with handles (§5.2) | all zone features |
| `listLocalSnapshots()` | `tmutil listlocalsnapshots /`, returns Time Machine snapshots only | Thin Time Machine snapshots (4) |
| `listPackageReceipts()` | `pkgutil --pkgs`, minus `com.apple.*` | Uninstaller (5) |
| `spotlightStatus()` | `mdutil -s` for each local volume | Reindex Spotlight (4) |

### 6.3 Changing (admin authentication, §7)

| Operation | Arguments the app may send | Helper checks | Command or API | Features |
|---|---|---|---|---|
| `remove(handles, dryRun)` | handles from `scan` | §5.3; launch items are booted out first (`launchctl bootout system/<label>` or `gui/<uid>/<label>`) | `unlinkat` / `fts`, or move to Trash | Cleanup, Applications rows above |
| `forgetReceipt(pkgID, dryRun)` | a package ID | must be in the current `pkgutil --pkgs` list and not `com.apple.*` | `pkgutil --forget <id>` | Uninstaller (5) |
| `flushDNS()` | none | none | `dscacheutil -flushcache`, then `killall -HUP mDNSResponder` (Mole's fallback for newer macOS noted in 004) | Flush DNS cache (4) |
| `reindexSpotlight(volumeUUID, dryRun)` | a volume UUID | must be a mounted, local, non-system-snapshot volume | `mdutil -E <mount point>` | Reindex Spotlight (4) |
| `deleteLocalSnapshot(date, dryRun)` | a snapshot date | must be in the current `listLocalSnapshots()` result, name `com.apple.TimeMachine.*` | `tmutil deletelocalsnapshots <date>` | Thin Time Machine snapshots (4) |
| `setDaemonEnabled(handle, enabled, dryRun)` | a handle from `scan(launchItems)` for a plist in `/Library/LaunchDaemons` | §5.3; label read by the helper from the plist; not `com.apple.*` | `launchctl disable\|enable system/<label>`, then `bootout` or `bootstrap system <plist>` | Background items (4) |
| `restoreTrashed(ledgerIDs)` | IDs from the helper's ledger | must be in the ledger, item still in the Trash, original location free | move back, restore owner and mode | Undo safety (12) |
| `emptyTrashed(ledgerIDs)` | IDs from the ledger | as above, except the original location may be taken | delete | Trash bins (2) |

Toggling agents in `/Library/LaunchAgents` needs no helper: they run in John's own `gui/<uid>` domain, so the app uses `launchctl disable|enable gui/<uid>/<label>` itself. Flush DNS, reindex Spotlight and thin Time Machine snapshots are the three v1 maintenance tasks that use the helper (ticket 001).

Rules for every command the helper runs:
- Absolute paths only (`/usr/bin/tmutil`, …), through `Process` with an argument array. Never a shell, never `PATH`, an empty environment.
- Arguments are only values the helper itself just read from the system (the "must be in the current list" column), so the app can only choose, never invent.
- A timeout per command (30 s; 10 minutes for `mdutil -E` start-up).

One job runs at a time. Progress and per-item results come back through a reply block per item, so the app can show progress and write its run log.

### 6.4 Deliberately not offered

Dropped in ticket 001 or harmful per research 004, so they never get an operation:
`purge` (Free up RAM), `periodic` scripts, repair permissions / `diskutil resetUserPermissions`, language-file stripping, `lipo` thinning, Speed up Mail, Wi-Fi network removal, `log erase` or anything in the unified log store, purgeable-space tricks (purgeable space is a read-only figure the app gets without root), secure shredding, editing `/System` or any app bundle in place, reading or writing `TCC.db`, Endpoint Security.

Also out: anything that only needs the user's own rights stays in the app (user caches, user logs, Xcode junk, AI models, Downloads, duplicates, user launch agents, user-owned apps).

## 7. Authentication for changes

Approving the helper in Login Items is a one-time "this app may have a root helper". It is not consent for each action. Following Apple DTS advice (research 002), changing operations also need an admin authentication:

- The helper, being root, registers the right `io.github.joswalt.TidyMyMac.helper.modify` in the authorization database on first launch: class `user`, group `admin`, `shared` false, **timeout 300 s**.
- The app calls `AuthorizationCopyRights` for that right (this shows the system password dialog), externalises it with `AuthorizationMakeExternalForm`, and sends it with each changing request.
- The helper checks the right with `AuthorizationCopyRights` and no interaction flag. If it fails, the operation is refused with `needsAuthorization`.
- Result: one password prompt per cleanup run (or per 5 minutes), never one per item. Whether the dialog offers Touch ID for our right is untested; it makes no difference to the design.
- Read-only operations and `flushDNS()` need no prompt.
- A Tidy Up run asks for the password once, at the start of the run, and only if the reviewed selection contains a changing helper operation.

## 8. Trash, undo and logs

**Trash for root-owned items.** `FileManager.trashItem` run as root would put items in root's Trash, which John never sees. Instead the helper moves trashed items into the calling user's Trash (`/Users/<user>/.Trash`, user found from the XPC connection's audit token), with a unique name if one already exists. The item keeps its owner (usually root). Two consequences:
- Finder's **Empty Trash** asks for an admin password for those items, as it does when you drag a root-owned app to the Trash yourself. TidyMyMac's own Trash bins feature empties them through `emptyTrashed`.
- Finder's **Put Back** does not work for them. TidyMyMac offers **Restore** through `restoreTrashed`.

**Ledger.** The helper records every item it moved to the Trash in `/Library/Application Support/TidyMyMac/trash-ledger.json` (root-owned, mode 644): original path, Trash path, owner, mode, time, run ID. Entries whose Trash item has gone are dropped on each read. `restoreTrashed` and `emptyTrashed` only accept ledger entries, so they cannot become an "any path" operation.

**Logs.** Every operation returns per-item results (path, bytes, action, success or error) to the app, which writes them into its run log (the "every run logged" rule; format decided with ticket 006 or the handoff). The helper also logs to the unified log under subsystem `io.github.joswalt.TidyMyMac.helper` and appends a one-line summary per job to `/Library/Logs/TidyMyMac/helper.log`, excluded from the `systemLogs` zone.

## 9. Signing and caller checks

**Signing.** Both targets: Personal Team "Apple Development" identity (team `26TUUFN7M2`), **Hardened Runtime on**, App Sandbox off, no extra entitlements (none of the operations need one). Same identity for Debug and Release. Never "Sign to Run Locally": in spike 009 an ad hoc build made launchd refuse to start the helper (`EX_CONFIG`).

**Builder setup check (from spike 009).** A fresh Personal Team certificate shows as "not valid" and `codesign` fails with `errSecInternalComponent` unless the keychain has Apple's **WWDR G3** intermediate. The setup docs must say: import `AppleWWDRCAG3.cer` from https://www.apple.com/certificateauthority/ into the login keychain, then check with `security find-identity -v -p codesigning`.

**Certificate renewal.** The current certificate is valid until **2027-11-07**. Xcode renews it with the same Team ID, so the requirement strings still match and re-approval is probably not needed (untested). If renewal does break it, the health check in §4.3 falls through to Repair helper; nothing else changes.

**Helper checks the app.** On the listener: `NSXPCListener.setConnectionCodeSigningRequirement` (macOS 13+) with

```
anchor apple generic and identifier "io.github.joswalt.TidyMyMac"
  and certificate leaf[subject.OU] = "<TEAM_ID>"
```

The helper also refuses a caller whose uid is not in the `admin` group.

**App checks the helper.** On its connection: `NSXPCConnection.setCodeSigningRequirement` with the same string, but `identifier "io.github.joswalt.TidyMyMac.Helper"`.

`TEAM_ID` comes from `Config/Identity.xcconfig` and is compiled into both targets as a constant; it is never read at runtime from a file.

**If John later pays $99:** switch to Developer ID Application, notarize and staple, and change `TEAM_ID`. The requirement strings already match (`anchor apple generic` covers both certificate kinds). John re-approves the helper once.

## 10. Fallback (not built in v1)

Spike 009 proved the daemon works with free signing, so v1 builds only the daemon. Ad hoc signing does not work at all, so the old "plan B" is gone.

If a future macOS breaks the daemon, the one remaining fallback is a **one-shot mode**: `TidyMyMacHelper --oneshot <request.json>` runs a single request through the same `HelperCore` checks and exits. The app would run it through `NSAppleScript` `do shell script (quoted form of …) with administrator privileges`, with a password prompt each run and scan-and-act in one request. Because all the safety logic lives in `HelperCore`, only the transport would change. Don't build it unless it's needed.

## 11. Testing

- **`HelperCore` unit tests** run as a normal user against temporary folders, with zone roots injected. Cases: zone escape with `..`, symlinked item, symlinked parent, folder swapped for a symlink between scan and act, hard link, item replaced by a different inode, deny-list names, a delete request in a trash zone, an expired handle, flags (`chflags uchg`), `fts` not crossing a mounted disk image.
- **Dry run everywhere**, used by the app's review screen and by tests.
- **Manual check on John's Mac** with the first real build (spike 009 already proved install, approval and uid 0): dry-run every zone, real run on `systemCaches`, trash and restore one item from `launchItems`, trash one root-owned app from `rootApps` and restore it, rebuild and confirm the silent restart in §4.3, and check whether the password dialog offers Touch ID.

## 12. Questions answered since the draft

| Question | Answer | Source |
|---|---|---|
| Does a Personal Team–signed `SMAppService` daemon register, run as root and survive rebuilds? | Yes. One approval; rebuilds keep it, but the running helper must be restarted (§4.3) | spike 009 |
| Does the helper need Full Disk Access added by hand? | No, it inherits the app's entry | spike 009 |
| Does moving another developer's app to the Trash need App Management? | No; only changes inside the bundle do | ticket 008 |
| Wi-Fi SSIDs as root without Location Services? | Yes, but moot: Wi-Fi removal was dropped | spike 009, ticket 001 |
| Personal Team certificate lifetime? | 1 year (to 2027-11-07); renewal re-approval untested, handled by §4.3 | spike 009 |
| Mole's licence | Learn-only, settled in spec 006 §7 | spec 006 |
| Touch ID in the password dialog? | Untested, cosmetic; checked in the first-build manual run (§11) | — |

## 13. Later features that would need the helper

Not in v1 (ticket 001 marked them Later). Each would add one zone or operation and nothing else:

- **Deleted users:** zone `deletedUsers`, root `/Users/Deleted Users`, `*.dmg` and `*.sparseimage` files, action trash.
- **Extensions manager:** add `/Library/PreferencePanes` and `/Library/Internet Plug-Ins` to `libraryLeftovers`, or give them their own zone.
- **Updating non-Sparkle apps** in `/Applications` that are root-owned: a copy-and-swap operation, designed with that feature.
