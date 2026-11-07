# Spec 011: Menu bar monitors and alerts

Ticket: [011](../planning/tickets/011-menu-bar-monitors.md). Screen layout: [spec 007 §5](007-app-layout.md). Shared thresholds with Health: ticket [012](../planning/tickets/012-health-summary-and-reminders.md).

Status: agreed with John (2026-11-07, "I agree" to all seven recommendations).

## 1. Process and presence

- The menu bar extra is part of the main app: SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`. There is no separate helper app.
- Closing the main window leaves the app running in the menu bar only, with the activation policy switched to `.accessory` so the Dock icon is hidden. Opening the window switches it back to `.regular`.
- **Show in menu bar** is on by default. **Open at login** is off by default and uses `SMAppService.mainApp`. Both are in Settings.
- The menu bar shows the template sweep glyph only (style guide §6), with no live text. A small dot badge is added while an alert condition is active.

## 2. Monitors: data sources (all public, no root, no entitlement)

| Monitor | Source | Shown as |
|---|---|---|
| CPU | `host_statistics(HOST_CPU_LOAD_INFO)`; delta of user+system+nice ticks over total ticks between samples | Total %, sparkline of the last 60 samples |
| Memory | `host_statistics64(HOST_VM_INFO64)` × `vm_kernel_page_size`. Used = (internal − purgeable) + wired + compressor pages. Total = `sysctl hw.memsize`. Pressure = `sysctl kern.memorystatus_vm_pressure_level` (1/2/4) | "12.4 GB of 16 GB", pressure label Normal / Warning / Critical (green / yellow / red) |
| Storage | `URL(fileURLWithPath: "/")` resource values `volumeAvailableCapacityForImportantUsageKey` and `volumeTotalCapacityKey` (matches Finder "available") | "Free 84.2 GB of 494 GB" + bar |
| Network | `sysctl` `NET_RT_IFLIST2` → `if_msghdr2.ifm_data` 64-bit `ifi_ibytes`/`ifi_obytes`, summed over interfaces that are up, non-loopback, and physical (`en*`); `utun*`, `awdl*`, `llw*`, `bridge*`, `ap*`, `lo*` excluded so VPN traffic isn't double-counted. Rate = delta / elapsed | ↓ 1.2 MB/s ↑ 84 KB/s |
| Trash size (alert only) | `FileManager` enumerator over `~/.Trash`, summing `totalFileAllocatedSizeKey`. **Needs Full Disk Access** (ticket 008) | Used by the alert and Health |

- Not in v1: per-process top CPU/RAM list (only own-user processes are readable without root → Later), Free RAM (dropped), battery and devices (Later).
- `getifaddrs` is not used, because its `if_data` counters are 32-bit and wrap at 4 GB.

## 3. Refresh (energy)

| State | CPU | Network | Memory | Storage | Trash |
|---|---|---|---|---|---|
| Popover open | 1 s | 1 s | 2 s | on open + 30 s | not shown |
| Popover closed | none | none | none | alert check (§4) | on change (§4) |

- All timers use `tolerance` ≥ 10 % of the interval. Sampling stops when the popover closes. Everything pauses on `NSWorkspace.willSleepNotification` and on screen lock (`com.apple.screenIsLocked`), and resumes on wake or unlock.
- The CPU sparkline and network rate start fresh each time the popover opens. Nothing is kept in history while closed, by design.

## 4. Alerts

Both are on by default, each with its own switch in the popover and in Settings. They are delivered as `UNUserNotificationCenter` notifications. Permission is requested on first run, after setup. If permission is denied, the dot badge still works.

**Low disk space**
- Threshold: the shared **low-disk setting**, default **20 GB** (choices 10 / 20 / 50). This same setting is Health's orange free-space line; Health's red line is fixed at 10 GB and appears in Health only (ticket 012).
- Checked every 5 min (tolerance 60 s), on wake (`NSWorkspace.didWakeNotification`), and after any TidyMyMac cleanup or empty-Trash run.
- Fires once when free space drops below the line. It re-arms when free space is above line + 5 GB, or after 24 h if still below (one reminder a day at most).
- Notification: "Your startup disk has 14.8 GB free." Button: **Open Space Lens**.

**Full Trash**
- Threshold: the shared **Trash setting**, default **5 GB** (choices 1 / 5 / 10 / 20), also used by Health.
- Measured on start, then only when `~/.Trash` changes (`FSEventStream` on the folder, 30 s debounce).
- Only the user's own Trash on the startup volume; external-volume `.Trashes` are not counted in v1.
- Without Full Disk Access, the switch is disabled with the caption "Needs Full Disk Access", and the button opens first-run setup.
- Same fire / re-arm rule as low disk (re-arms below 80 % of the threshold or after 24 h).
- Notification: "Your Trash holds 7.3 GB." Button: **Review Trash**, which opens the app at Cleanup › Trash bins. The notification never empties anything.

## 5. Clicks and buttons

- CPU, Memory and Network rows open Activity Monitor (`com.apple.ActivityMonitor`). The Storage row opens Space Lens.
- Buttons: **Open TidyMyMac**, **Run Smart Care** (opens the window and starts the scan).
- Status pill: "All good", or the active alert ("Low disk space" / "Trash over 5 GB"); memory pressure Critical also shows here.

## 6. Units and formatting

- Bytes use `ByteCountFormatter` with `.file` style (decimal, like Finder). Network uses KB/s and MB/s (decimal).
- CPU is a whole-number percentage.

## 7. Left for the build

- Check that `kern.memorystatus_vm_pressure_level` is readable from a non-sandboxed user app on macOS 14 and 26. Fall back to `DispatchSource.makeMemoryPressureSource` events if it isn't.
- Confirm that the FSEvents stream on `~/.Trash` delivers events with Full Disk Access granted (ticket 008 found that listing needs FDA).
