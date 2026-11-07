# CleanMyMac feature list (for TidyMyMac scoping)

Compiled 2026-11-07 from public sources only (MacPaw's knowledge base, a 2026 review, MacRumors). No binaries were downloaded or inspected.
Mark each row **Keep / Later / Drop** in the last column.

Legend for "Notes": **AS** = missing or limited in the Mac App Store edition (sandbox limits, a useful hint about what needs elevated privileges).

## 1. Smart Care (one-click scan)
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Smart Care scan | One button runs Cleanup, Protection, Performance, Applications and My Clutter checks, then shows a reviewable list of actions | Core UX | Keep |
| Review before run | Every proposed deletion or task can be inspected and unticked first | | Keep |

## 2. Cleanup (system junk)
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| User cache files | Clears per-user app caches in ~/Library/Caches | | Keep |
| System cache files | Clears system-level caches | AS | Keep |
| User log files | Removes per-user app logs | | Keep |
| System log files | Removes system-level logs | AS | Keep |
| Language files | Strips unused .lproj localizations from apps | AS, can break code signatures | Drop |
| Universal binaries | Removes unused CPU architecture slices from apps | AS, can break code signatures | Drop |
| Document versions | Purges stored old versions of documents | | Later |
| Broken preferences | Deletes corrupt or orphaned .plist files | | Later |
| Broken login items | Removes login entries pointing to missing apps | AS | Keep |
| Deleted users | Removes data left from deleted user accounts | AS | Later |
| iOS device backups | Finds old iPhone/iPad backups | AS | Keep (review only) |
| Xcode junk | DerivedData, archives, old simulators and device support | | Keep |
| AI junk files | Leftover caches from AI tools | New in 2025 | Keep |
| Local AI models | Finds large locally stored models (Ollama, LM Studio, etc.) | New in 2025 | Keep (review only) |
| Mail attachments | Removes locally downloaded Mail attachments | | Later |
| Trash bins | Empties startup-drive, external-drive and Mail trash | | Keep |
| Ignore list / safety database | Excludes chosen items; uses a curated list of what is safe to delete | Key to safety | Keep |

## 3. Protection
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Malware scan | Quick, Balanced or Deep scan for adware, ransomware, miners etc. (Moonlock engine) | Needs a threat signature source | Later |
| Real-time monitor | Watches downloads, DMGs and attachments for malware | AS | Later |
| Privacy: browsers | Clears history, cookies, caches for Safari, Chrome, Firefox | Safari is AS | Later |
| Privacy: recent items | Clears recent files/apps/servers lists | | Later |
| Privacy: Wi-Fi networks | Removes saved Wi-Fi networks | AS | Drop |
| Application permissions | Shows which apps have camera, mic, screen recording, etc. access and how to revoke | | Keep (read-only, links to System Settings) |

## 4. Performance
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Free up RAM | Purges inactive memory | AS | Drop |
| Free up purgeable space | Forces macOS to release purgeable storage | AS | Drop (show as read-only figure) |
| Flush DNS cache | Resets the DNS resolver cache | AS, needs admin | Keep |
| Run periodic/maintenance scripts | Triggers macOS housekeeping scripts | AS, needs admin | Drop |
| Reindex Spotlight | Rebuilds the Spotlight index | AS | Keep |
| Repair disk permissions | Fixes home-folder permission issues | AS | Drop |
| Speed up Mail | Vacuums/reindexes the Mail database | AS | Drop |
| Thin Time Machine snapshots | Deletes local APFS snapshots | AS | Keep |
| Login items | List, enable and disable apps that start at login | | Keep |
| Background items | Manage launch agents/daemons running in the background | | Keep |

## 5. Applications
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Uninstaller | Removes an app plus its support files, caches, prefs, launch agents | Flagship feature | Keep |
| Unused apps | Flags apps not opened in a long time | | Keep |
| Leftover files | Finds remnants of apps already deleted | | Keep |
| Installer leftovers | Finds old .dmg/.pkg installers | | Keep |
| Updater: Sparkle apps | Detects and installs updates via each app's Sparkle feed | | Keep (check only) |
| Updater: other apps | Updates apps from other sources (MacPaw's own update catalog) | Needs a version database | Later |
| Updater: App Store / macOS | Detects available updates (cannot install outside the App Store) | | Keep (macOS check only; App Store left out) |
| Extensions manager | Lists and removes Safari/browser extensions, plug-ins, widgets, prefpanes | Was in CleanMyMac X; folded into other modules now | Later |

## 6. My Clutter (personal files)
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Large & old files | Finds big or long-untouched files, filterable by type/size/date | | Keep |
| Duplicates | Finds byte-identical files across folders, with auto-select rules | | Keep |
| Similar images | Groups visually similar photos (bursts, near-duplicates) | Needs perceptual hashing / Vision | Later |
| Downloads review | Reviews Downloads from Safari, Chrome, Slack | | Keep |
| Duplicate downloads | Finds repeat downloads of the same file | | Keep |

## 7. Space Lens
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Storage map | Interactive bubble map of folder sizes with drill-down | | Keep |
| Size-ranked list | Sortable list beside the map; select and remove from there | | Keep |
| Scan a specific folder or drive | Limits the map to one location | | Keep |

## 8. Cloud Cleanup (added mid-2025)
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Cloud storage dashboard | One view of iCloud Drive, Google Drive, OneDrive, Dropbox | Needs OAuth per service | Later |
| Local vs. cloud usage | Shows which synced files take local disk space; offload or delete | | Later |

## 9. My Tools
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Tool shortcuts | ~22 single-purpose tools (each module above as a standalone action) | | Keep |
| Pinned tools and workflows | Pin favourites and chain them into reusable routines | | Later |
| Screen cleaning mode | Locks keyboard and trackpad so you can wipe the screen | | Later |
| Shredder | Securely erases files | CleanMyMac X only; not in current list | Drop |

## 10. My Activity / Health
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Mac Health summary | Overall health score and status | | Keep (simple summary) |
| Recommendations / Assistant | Suggests the next maintenance actions | | Later |
| Usage statistics | History of what was cleaned and app usage | | Keep (run history) |
| Scheduled scans and reminders | Periodic nudges to run Smart Care | | Keep (reminders only) |

## 11. Menu bar app ("The Menu")
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| CPU, RAM, storage, network monitors | Live stats with quick actions such as Free RAM | | Keep |
| Battery monitor | Battery health, cycles, apps draining power | | Later |
| Connected devices | Bluetooth device battery levels, external drives with eject | | Later |
| Protection status | Shows real-time protection state | AS | Later |
| Alerts | Low disk space, low external drive space, heavy RAM, hung apps, battery drain, low Bluetooth battery, full trash, malware found, outdated apps, "uninstall apps correctly" when an app is dragged to Trash | | Keep (low disk, full Trash only; rest Later) |

## 12. Platform / cross-cutting
| Feature | What it does | Notes | Keep? |
|---|---|---|---|
| Privileged helper tool | Root helper for system-level cleanup | Required for most AS-marked rows | Keep |
| Full Disk Access onboarding | Guides the user through granting FDA | | Keep |
| Undo safety | Moves items to Trash rather than hard-deleting where possible | | Keep |
| Licensing / subscription | Plans, payment-detail alerts | Probably drop for a personal app | Drop |

---

## About rea (morluto/rea)
rea is an MIT-licensed MCP server and CLI that lets an AI agent reverse engineer software: it drives tools like Ghidra, Hopper or IDA on native binaries (including Mach-O), inspects Electron/JS and .NET apps, and captures runtime behaviour on macOS and Linux, returning pseudocode, strings, symbols and call graphs as evidence. For TidyMyMac it could help us learn *how* CleanMyMac finds things (for example which paths its cleanup rules target), but it is not needed to build these features, since nearly all of them are well-documented macOS APIs and file locations.

## Licensing notes
- **Fine:** reimplementing the same features and ideas under our own name, UI and code.
- **Not fine:** copying MacPaw code, rule databases, malware signatures, icons, sounds, illustrations, or the CleanMyMac name and look.
- **Risky:** decompiling CleanMyMac with rea. MacPaw's EULA almost certainly forbids reverse engineering, and anything learned that way could taint our code. A clean-room approach (observe behaviour and public docs, write our own code) is safer.
- **Third-party deps:** a malware scanner needs our own signature source (e.g. ClamAV, GPL, or Apple XProtect rules on-device).

## Sources
- MacPaw: Feature availability and differences — https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans
- MacPaw: Start Smart Scan — https://macpaw.com/support/cleanmymac/knowledgebase/start-smart-scan
- The Sweet Bits 2026 review — https://thesweetbits.com/tools/cleanmymac
- MacRumors on the 2024 redesign — https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/
- rea — https://github.com/morluto/rea
