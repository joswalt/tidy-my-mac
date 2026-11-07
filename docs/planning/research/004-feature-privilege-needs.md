# 004: What each CleanMyMac-style feature needs on macOS 14+ (Apple Silicon)

Researched 2026-11-07 for TidyMyMac. Input: `/mnt/project-files/tidymymac/cleanmymac-feature-list.md` (every feature row covered, same module order).
Method: Apple developer documentation and DTS answers on the Apple Developer Forums, macOS man pages, and the source of Mole (`tw93/Mole`, MIT, an open-source macOS cleaner; commit `3c9eb9a`) as a reference implementation. CleanMyMac itself was not downloaded or inspected. Where a claim rests on a secondary source (Eclectic Light Co., heise) it is marked as such.

## Key findings

1. **Ship outside the Mac App Store.** The App Sandbox blocks most of this catalogue: helper tools, other apps' data, system paths. Use Developer ID signing plus notarization.
2. **Full Disk Access (FDA) is the main gate, not root.** Safari data, Mail, `~/Library/Containers` of other apps (macOS 14 added a prompt for reading other apps' containers), iOS backups, `~/.Trash` and the TCC database all need FDA. Apple offers **no API to check for FDA or request it** (Quinn, Apple DTS): probe a protected path and deep-link to System Settings.
3. **Root is needed for a small set of actions only:** system caches and logs, `purge`, `mdutil -E`, DNS flush, deleted-user data, Wi-Fi removal, `/Library/LaunchDaemons`, and deleting root-owned apps. Do these through a single `SMAppService.daemon` helper (macOS 13+) that talks over XPC and checks the caller's code-signing requirement. `SMJobBless` is deprecated.
4. **Changing other apps' bundles is restricted.** Since macOS 13 the **App Management** TCC permission gates changes to other teams' app bundles. Any edit to a signed bundle breaks its seal ("a sealed resource is missing or invalid"). This is what makes language stripping and architecture thinning dangerous, and why updaters must copy and swap rather than patch.
5. **Obsolete or harmful:** repair permissions (SIP since 10.11), periodic scripts (`periodic` removed in macOS 15), free RAM (`purge` defeats the file cache), secure shredding (meaningless on SSD/APFS; Apple removed Secure Empty Trash in 10.11 and `srm` in 10.12), and language/architecture stripping (breaks signatures; low value). "Free purgeable space" has no API and fights the OS.

Legend: **Root** = needs the privileged helper; **FDA** = Full Disk Access; **TCC** = another privacy permission; **Private** = relies on undocumented API or file formats. Verdicts: **OK** / **Caution** / **Obsolete** / **Harmful**.

## 1. Smart Care
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Smart Care scan | Orchestration of the scanners below (Swift concurrency, `FileManager`) | Only for root sub-tasks | FDA for full coverage | No | Inherits each sub-task's needs; must degrade gracefully without FDA | OK |
| Review before run | App UI; a dry-run model, as in Mole's `--dry-run` | No | No | No | Essential safety feature | OK |

## 2. Cleanup
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| User cache files | `FileManager` on `~/Library/Caches/*` | No | FDA for sandboxed apps' caches under `~/Library/Containers/*/Data/Library/Caches` (macOS 14 app-data protection) | No | Running apps can crash or re-download data; skip running apps and keep an allow/deny list. Mole keeps a whitelist | OK |
| System cache files | `/Library/Caches`; `/System/Library/Caches` is SIP-protected and off-limits | Yes | No | No | Small gains; some caches (e.g. font, `dyld`) are rebuilt at boot cost | Caution |
| User log files | `~/Library/Logs` | No | No | No | Low value; logs help diagnose problems | OK |
| System log files | `/Library/Logs`, `/private/var/log`; unified log only via `log erase` | Yes | No | No | The unified log (`/var/db/diagnostics`) is self-managed by `logd`; erasing it destroys diagnostics | Caution |
| Language files | Deleting `*.lproj` inside app bundles | Yes for root-owned apps | App Management (macOS 13+) | No | **Breaks the bundle's code-signature seal** ("a sealed resource is missing or invalid"); Gatekeeper may refuse launch; App Store and auto-updated apps revert or break. Tiny savings | **Harmful** |
| Universal binaries | `lipo -remove` / `-thin` (lipo ships only with the Command Line Tools) | Yes for root-owned apps | App Management | No | Thinning a hash-sealed file breaks the seal. Mole's `slim` only thins nested code sealed by cdhash, only for Developer ID apps (skips App Store and Apple apps), works on a clone, runs `codesign --verify --deep --strict` and then swaps. Updates restore the slices; Rosetta-preferring apps lose x86_64 | **Harmful** unless done the Mole way |
| Document versions | `NSFileVersion.removeOtherVersionsOfItem(at:)` per file; the store `/.DocumentRevisions-V100` is root-only, with an undocumented format | Per-file API: no; store: yes | FDA for some paths | Store format is private | Users lose Versions history; use the per-file public API | Caution |
| Broken preferences | `PropertyListSerialization` / `plutil -lint`; remove with `defaults delete <domain>` because `cfprefsd` caches prefs | No (user domain) | FDA for container prefs | No | Never touch `~/Library/Containers`/`Group Containers` prefs (Eclectic Light advice). "Orphaned" detection is heuristic; a false positive loses settings | Caution |
| Broken login items | Legacy: `~/Library/LaunchAgents` plists whose `Program` is missing (`launchctl bootout gui/<uid>`); `/Library/LaunchAgents\|Daemons` need root. Modern login items live in the Background Task Management (BTM) store | Root for `/Library` | No | **BTM store is private**; `sfltool dumpbtm` (root) only reads it | You cannot remove another app's `SMAppService` item via API; send the user to `SMAppService.openSystemSettingsLoginItems()` | Caution |
| Deleted users | `/Users/Deleted Users/*.dmg` and orphaned `/Users/<name>` | Yes | FDA | No | Irreversible; confirm against `dscl . list /Users` | Caution |
| iOS device backups | `~/Library/Application Support/MobileSync/Backup` | No | **FDA** | `Info.plist`/`Manifest.db` format is undocumented but stable | Backups may be the only copy of device data; review, don't auto-delete | OK (review only) |
| Xcode junk | `~/Library/Developer/Xcode/DerivedData`, `Archives`, `iOS DeviceSupport`; `xcrun simctl delete unavailable`, `xcrun simctl runtime delete` | No (runtimes may need admin) | No | No | Archives hold dSYMs needed for crash symbolication; Mole skips when Xcode or Simulator is running | OK |
| AI junk files | Known cache paths (e.g. `~/.cache/huggingface`, app caches) | No | No | No | Path list will rot; keep it data-driven | OK |
| Local AI models | Known locations, e.g. `~/.ollama/models`, `~/.lmstudio/models`, `~/.cache/huggingface/hub` | No | No | No | Large re-downloads; review only. Ollama blobs are shared between models | OK (review) |
| Mail attachments | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`, attachments under `~/Library/Mail/V*` | No | **FDA** (Mail data is TCC-protected) | Mail store layout is undocumented | Deleting from inside the store can desync Mail; restrict to the Mail Downloads cache | Caution |
| Trash bins | `~/.Trash`, `/Volumes/*/.Trashes/<uid>`; or Finder via Apple Events (`empty trash`) | No | FDA to read `~/.Trash`; **Automation** (Apple Events) permission if scripting Finder/Mail | No | Irreversible by definition | OK |
| Ignore list / safety database | App data (JSON/SQLite) shipped with the app; never MacPaw's rules | No | No | No | The real safety mechanism; Mole uses a whitelist plus protected-path validation | OK (required) |

## 3. Protection
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Malware scan | Own scanner (e.g. YARA) over files; signature sources: ClamAV (GPL) or the on-device XProtect YARA rules in `/Library/Apple/System/Library/CoreServices/XProtect.bundle` | No (root for system paths) | FDA | XProtect rule format is unofficial and Apple-owned (licensing unclear) | False positives; the signature feed is the hard part. macOS already runs XProtect and XProtect Remediator | Caution |
| Real-time monitor | Proper route: **Endpoint Security** system extension (`com.apple.developer.endpoint-security.client` entitlement, granted by Apple on request) needing FDA and user approval. Light route: FSEvents on Downloads plus quarantine xattr | ES: runs as root | FDA | No | The ES entitlement needs Apple approval; FSEvents is after-the-fact only | Caution |
| Privacy: browsers | Safari: `~/Library/Safari`, `~/Library/Containers/com.apple.Safari`; Chrome/Firefox: profile SQLite in `~/Library/Application Support` | No | **FDA for Safari**; none for Chrome/Firefox | Browser DB schemas are undocumented | The browser must be quit (SQLite locks); deleting cookies logs users out. Safari history deletion is better left to Safari | Caution |
| Privacy: recent items | `~/Library/Application Support/com.apple.sharedfilelist/*.sfl3`; `NSDocumentController.clearRecentDocuments` works only for your own app | No | Possibly FDA | **sfl3 format is private** | Edits may be overwritten by `sharedfilelistd`; Mole has a "repair shared file lists" task | Caution |
| Privacy: Wi-Fi networks | `networksetup -removepreferredwirelessnetwork <if> <SSID>` or CoreWLAN `CWMutableConfiguration` + `commitConfiguration` | Yes (admin auth) | **Location Services** is needed to read SSIDs on macOS 14+ | No | Can strand the user offline; synced via iCloud Keychain, so it may come back | Caution |
| Application permissions | Show: no API; `TCC.db` is FDA-protected and "not API" (Quinn). Revoke: `tccutil reset <Service> <bundle-id>` and deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_*` | No (reading the system TCC.db needs FDA) | FDA to read | **TCC.db schema is private** | Schema changes between releases; read-only display plus deep links is the safe design | Caution |

## 4. Performance
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Free up RAM | `/usr/sbin/purge` (flushes the disk cache) | Yes | No | No | Throws away useful file cache, so the next work is slower; memory compression and pressure handling make it pointless. Show memory pressure instead (`host_statistics64`, `memory_pressure`) | **Obsolete** |
| Free up purgeable space | No public API. Report with `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` vs `volumeAvailableCapacityKey`; the only lever is thinning snapshots or filling the disk to make `deleted` purge | Snapshot thinning: yes | No | No | `deleted` frees it on demand anyway; the "fill the disk" trick is risky | **Obsolete** (report only) |
| Flush DNS cache | `dscacheutil -flushcache` then SIGHUP to mDNSResponder (`launchctl kill SIGHUP system/com.apple.mDNSResponder[.reloaded]` or `killall -HUP mDNSResponder`) | Yes | No | No | Mole notes a newer macOS refuses the launchctl signal even to root and falls back to `sudo -u _mdnsresponder killall -u _mdnsresponder -HUP`; skip under VPN | OK (niche) |
| Run periodic/maintenance scripts | `periodic daily weekly monthly` | Yes | No | No | Apple stopped using `periodic` in macOS 14 and **removed it in macOS 15** (heise); `logd` and launchd jobs handle it now | **Obsolete** |
| Reindex Spotlight | `mdutil -E /` (erase and rebuild); `mdutil -s` for status | Yes | No | No | Hours of heavy CPU and I/O on large disks; only when search is broken | Caution |
| Repair disk permissions | Disk Utility repair removed in 10.11 (SIP); `diskutil resetUserPermissions / <uid>` (root) still exists; `repairHomePermissions` in Recovery | Yes | No | No | Apple withdrew the advice; Eclectic Light warns `repairHomePermissions` can lock users out of folders. Mole still offers `resetUserPermissions` only when it detects issues | **Obsolete** / harmful |
| Speed up Mail | `sqlite3 "~/Library/Mail/V10/MailData/Envelope Index" VACUUM` with Mail quit; Apple's supported path is Mailbox › Rebuild | No | **FDA** | Mail's DB is undocumented | Corruption if Mail is running; Mole checks integrity and skips if the app runs | Caution |
| Thin Time Machine snapshots | `tmutil listlocalsnapshots /`, `tmutil deletelocalsnapshots <date>`, `tmutil thinlocalsnapshots / <bytes> <urgency 1-4>` | Yes (delete/thin) | No | No | Loses local restore points; third-party snapshots (CCC, Synology) belong to their apps. Mole only reports them | Caution |
| Login items | Own app: `SMAppService.mainApp`/`.loginItem`. Others: no public list or toggle API; BTM store is private; `SMAppService.statusForLegacyPlist(at:)` checks legacy plists; deep-link via `openSystemSettingsLoginItems()` | No | No | Listing others = **private** (BTM) or `sfltool dumpbtm` (root, unsupported output) | Read-only list plus deep link is the safe design | Caution |
| Background items | `launchctl print` / `bootout` for `~/Library/LaunchAgents` (user) and `/Library/LaunchAgents\|Daemons` (root) | Yes for `/Library` | No | No | Disabling vendor daemons (VPN, security, drivers) breaks software; BTM may re-enable them | Caution |

## 5. Applications
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Uninstaller | `NSWorkspace.recycle` / `FileManager.trashItem`; find related files by bundle ID and team ID in `~/Library/{Application Support,Caches,Preferences,Containers,Group Containers,LaunchAgents,Saved Application State}`; `launchctl bootout`; `pkgutil --pkgs/--files/--forget` for receipts; `lsregister -u` to unregister | For root-owned apps, `/Library` items and `pkgutil --forget` | **App Management** (deleting other teams' apps, macOS 13+); FDA for containers | No | Shared group containers and same-vendor suites: Mole keeps data other installed copies still use | OK (flagship) |
| Unused apps | Spotlight `kMDItemLastUsedDate` via `NSMetadataQuery`/`MDItem` | No | No | No | Not every launch updates the date; treat as a hint | OK |
| Leftover files | Same paths as the uninstaller, matched against installed bundle IDs (`LSCopyApplicationURLsForBundleIdentifier` / `NSWorkspace.urlsForApplications(withBundleIdentifier:)`) | Root for `/Library` | FDA | No | Heuristic matching: biggest false-positive risk in the app | Caution |
| Installer leftovers | Spotlight query for `com.apple.disk-image`, `com.apple.installer-package-archive` | No | Downloads folder TCC prompt | No | Low risk | OK |
| Updater: Sparkle apps | Read `SUFeedURL` from the app's Info.plist, fetch the appcast, compare `sparkle:version` to `CFBundleVersion`; verify the EdDSA signature (`SUPublicEDKey`) and code signature; copy, update, swap atomically (`renamex_np`) | Root-owned apps | App Management | No | Apple DTS: never patch an app in place or after it has run. Simplest safe option: open the app and let its own Sparkle update run | Caution |
| Updater: other apps | Needs a version catalogue, e.g. the Homebrew Cask JSON API | Depends | App Management | No | Third-party catalogue trust and licensing; supply-chain risk | Later |
| Updater: App Store / macOS | macOS: `softwareupdate --list` (no root to list). App Store: no public API (the `mas` CLI uses private frameworks) | No | No | App Store = **private** | Detection only; open the App Store to install | OK (macOS) / Caution (MAS) |
| Extensions manager | `pluginkit -m` (list), `pluginkit -e ignore\|use -i <id>` (toggle) for app extensions (Safari, widgets, Finder Sync, Share); `/Library/PreferencePanes`; Chrome/Firefox profile extension folders | Root for `/Library` | No | `pluginkit` is shipped but lightly documented | NPAPI internet plug-ins are dead; Safari extensions should be managed in Safari Settings | Caution |

## 6. My Clutter
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Large & old files | `FileManager.enumerator` with `.totalFileAllocatedSizeKey`, `.contentAccessDateKey`; `getattrlistbulk` for speed | No | FDA for full coverage; Desktop/Documents/Downloads TCC prompts | No | Access dates are unreliable (`noatime`-like behaviour); count allocated size, not logical size | OK |
| Duplicates | Group by size, then hash (CryptoKit SHA-256) | No | As above | No | **APFS clones share blocks**: deleting a clone frees almost nothing. Detect with `getattrlist` `ATTR_CMNEXT_CLONEID` or compare allocated space; never delete inside bundles or libraries (Photos, Music) | Caution |
| Similar images | Vision `VNGenerateImageFeaturePrintRequest` + `computeDistance`; Photos via PhotoKit | No | **Photos** permission; deletion via `PHAssetChangeRequest.deleteAssets` (system confirms) | No | Never touch the Photos library package directly | OK |
| Downloads review | `~/Downloads` plus `kMDItemWhereFroms` (xattr `com.apple.metadata:kMDItemWhereFroms`) | No | Downloads folder TCC prompt | No | Low risk | OK |
| Duplicate downloads | `name (1).ext` patterns plus hash equality | No | Downloads TCC | No | Same clone caveat | OK |

## 7. Space Lens
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Storage map | Recursive scan (`getattrlistbulk` / `FileManager`), allocated sizes; SwiftUI or Canvas treemap | No (root to size system dirs) | FDA for complete totals | No | Hard links and clones double-count; "System Data" can't be fully attributed without root | OK |
| Size-ranked list | Same data; delete through `trashItem` | No | As above | No | Block deletion under `/System`, inside bundles and inside libraries | OK |
| Scan a specific folder or drive | `NSOpenPanel`, `DiskArbitration` for volumes | No | Removable/network volume TCC prompts | No | | OK |

## 8. Cloud Cleanup
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Cloud storage dashboard | Remote quotas need each provider's OAuth API (Google Drive, Microsoft Graph, Dropbox). **iCloud quota has no public API** | No | No | iCloud quota = none | Token storage in the Keychain; maintenance of four APIs | Later |
| Local vs. cloud usage | `URLResourceKey.ubiquitousItemDownloadingStatusKey`, `.isUbiquitousItemKey`; evict iCloud items with `FileManager.evictUbiquitousItem(at:)`; File Provider files (`~/Library/CloudStorage`) via `fileproviderctl evict` (lightly documented) | No | FDA may be needed for `~/Library/CloudStorage` | `fileproviderctl` is undocumented | Never delete from a synced folder by mistake: deletes propagate to the cloud | Caution |

## 9. My Tools
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Tool shortcuts | App UI; optionally App Intents for Shortcuts | — | — | No | | OK |
| Pinned tools and workflows | App UI; App Intents | — | — | No | | OK |
| Screen cleaning mode | `CGEvent.tapCreate` that swallows keyboard and trackpad events | No | **Accessibility** (to block events; Input Monitoring alone only listens) | No | Must always provide an escape (timer or a key combination) | OK |
| Shredder | Overwrite-then-delete | No | — | No | Meaningless on SSD/APFS (copy-on-write, wear levelling, TRIM); Apple removed Secure Empty Trash (10.11) and `srm` (10.12). FileVault is the real answer | **Obsolete** |

## 10. My Activity / Health
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Mac Health summary | Aggregate of the stats below | No | No | No | A score invites "fix-it" theatre; keep it honest | OK |
| Recommendations / Assistant | App logic | No | No | No | | OK |
| Usage statistics | Own operation log (Mole writes `~/Library/Logs/mole/operations.log`) | No | No | No | App-usage history from `knowledgeC.db` is private and FDA-gated, so skip it | OK |
| Scheduled scans and reminders | `SMAppService.agent` or `.mainApp` login item + `UNUserNotificationCenter` | No | **Notifications** permission | No | Appears in Login Items; the user can disable it | OK |

## 11. Menu bar app
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| CPU, RAM, storage, network monitors | `host_processor_info`, `host_statistics64` (Mach), `sysctl`, `getifaddrs` byte counters, volume capacity keys; `MenuBarExtra` (SwiftUI) | No | No | No | Per-process network usage needs private `NetworkStatistics`; avoid | OK |
| Battery monitor | `IOPSCopyPowerSourcesInfo` (IOKit.ps, public); cycle count and health from IORegistry `AppleSmartBattery` (keys undocumented) | No | No | IORegistry keys undocumented | "Apps draining power": no public per-app energy API (Activity Monitor uses private APIs) | Caution |
| Connected devices | Volumes: `DiskArbitration`, `NSWorkspace.unmountAndEjectDevice(at:)`. Bluetooth battery: no public API (IORegistry `BatteryPercent` keys / `system_profiler SPBluetoothDataType`) | No | **Bluetooth** permission for CoreBluetooth | Battery levels = undocumented | Bluetooth battery may break across releases | Caution |
| Protection status | Own state | No | No | No | | OK |
| Alerts | Disk: capacity keys; RAM: `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`; hung apps: no public API (heuristics); app dragged to Trash: FSEvents on `~/.Trash` | No | FDA for `~/.Trash`; Notifications | Hung-app detection = heuristic or private | Too many alerts annoy; make each optional | Caution |

## 12. Platform / cross-cutting
| Feature | API / tool | Root | FDA / TCC | Private API | Risks and notes | Verdict |
|---|---|---|---|---|---|---|
| Privileged helper tool | `SMAppService.daemon(plistName:)` (macOS 13+) with the plist in `Contents/Library/LaunchDaemons`; `NSXPCConnection` with `setCodeSigningRequirement` on both ends | It is root | User approves in Login Items | No | Attack surface: expose a narrow, typed XPC API (no "run arbitrary command"); `SMJobBless` and `AuthorizationExecuteWithPrivileges` are deprecated. Not allowed in the App Sandbox | Required |
| Full Disk Access onboarding | No check/request API (Quinn, DTS): probe a protected path (e.g. `~/Library/Safari`) and deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` | No | FDA | No | Grant applies to the signed app's identity; re-signing or moving builds can confuse TCC during development | Required |
| Undo safety | `FileManager.trashItem(at:resultingItemURL:)` / `NSWorkspace.recycle` | No | No | No | Root-owned items trashed by the helper land in root's Trash; plan for it | Required |
| Licensing / subscription | None for a personal app (StoreKit only on the App Store) | — | — | — | | Drop |

## Flagged features
- **Harmful:** Language files, Universal binaries (signature breakage, App Management, small gains; only acceptable with Mole-style clone + `codesign --verify` + swap), Repair disk permissions (`repairHomePermissions` can lock users out).
- **Obsolete:** Free up RAM (`purge`), Run periodic scripts (removed in macOS 15), Repair disk permissions (SIP since 10.11), Shredder (SSD/APFS), Free up purgeable space (no API; the OS manages it).
- **Rely on private or undocumented formats:** listing other apps' login items (BTM), TCC permissions display, recent items (sfl3), App Store updates, Bluetooth battery, battery health keys, per-app energy, hung-app detection.
- **Needs Apple approval:** Real-time malware monitor via Endpoint Security (restricted entitlement).

## Sources
- Apple, `SMAppService` (macOS 13+; login items, agents, daemons, `openSystemSettingsLoginItems`, `statusForLegacyPlist`): https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple, Updating your app package installer to use the new Service Management API: https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api
- Apple, Protecting user data with App Sandbox: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- Apple, `NSFileVersion.removeOtherVersionsOfItem(at:)`: https://developer.apple.com/documentation/foundation/nsfileversion/removeotherversionsofitem(at:)
- Apple DTS (Quinn), no API to test for Full Disk Access; TCC.db location is not API: https://developer.apple.com/forums/thread/114452
- Apple DTS (Quinn), modifying a signed bundle is unsupported; copy-update-swap for updaters: https://developer.apple.com/forums/thread/766491
- Apple, Updating Mac Software: https://developer.apple.com/documentation/security/updating-mac-software
- Apple Developer Forums, App Management privacy setting (Ventura): https://developer.apple.com/forums/thread/715220
- Mole source, MIT, commit 3c9eb9a (`lib/optimize/tasks.sh`: DNS flush incl. mDNSResponder signal refusal, `periodic`, `diskutil resetUserPermissions`, SQLite VACUUM, `mdutil`; `lib/optimize/catalog.sh`; `lib/clean/snapshots.sh`; `bin/slim.sh` thinning with signature checks; `lib/clean/dev.sh` simctl): https://github.com/tw93/Mole
- `tmutil` local snapshot verbs (man page summarised by Eclectic Light, secondary): https://eclecticlight.co/2020/01/22/time-machine-11-tmutil/
- Local snapshots are purgeable and removed by `deleted` (Eclectic Light, secondary): https://eclecticlight.co/2026/08/24/arent-snapshots-purgeable/
- Repair permissions history, `resetUserPermissions`, `repairHomePermissions` risk (Eclectic Light, secondary): https://eclecticlight.co/2025/10/27/should-you-repair-permissions/
- macOS 15 removes `periodic` (heise, secondary): https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html
- Secure Empty Trash removed in El Capitan (Apple Developer Forums): https://developer.apple.com/forums/thread/12531
- Man pages consulted for command syntax: `purge(8)`, `dscacheutil(1)`, `mdutil(1)`, `tmutil(8)`, `diskutil(8)`, `networksetup(8)`, `tccutil(1)`, `pluginkit(8)`, `softwareupdate(8)`, `pkgutil(1)`, `lipo(1)`, `codesign(1)`.

## Open questions
- Exact scope of App Management for *deleting* (vs. modifying) another team's app from a Developer ID app on macOS 14/15: verify on a test machine.
- Whether `tccutil reset <Service> <bundle-id>` for system-level services (Screen Recording, Accessibility) needs root on macOS 14+.
- Whether `~/.Trash` listing needs FDA or only a Files & Folders prompt on macOS 14+: verify empirically.
