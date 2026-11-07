# Spec 012: Health summary and Tidy Up reminders

Ticket: [012](../planning/tickets/012-health-summary-and-reminders.md). Screens: [spec 007](007-app-layout.md) (Health module, Tidy Up Done screen). Shared alert settings: [spec 011](011-menu-bar.md). Agreed with John, 2026-11-07.

## 1. Health status

- No numeric score. One overall **status**: Looks good (green), Worth a look (orange), Needs attention (red).
- Overall status = the worst **signal**. Each signal is a row with its own dot, a one-line reason and one fix button.

| Signal | Orange | Red | Fix button |
|---|---|---|---|
| Free disk space (real free space, `volumeAvailableCapacityKey`; see spec 011 §2) | below the shared **low-disk setting** (default 20 GB; 10/20/50) | below 10 GB (fixed; Health only, no notification). If the setting is 10, it goes straight to red | Disk Map |
| Last Tidy Up | more than 2× the reminder interval ago, or never run | never | Run Tidy Up |
| Junk found last time | last scan found > 5 GB that was not cleaned | never | Tidy Up |
| Trash size (needs FDA; hidden without it) | above the shared **Trash setting** (default 5 GB; 1/5/10/20) | never | Empty Trash… (standard confirm) |
| Full Disk Access | off | never | Open setup |
| Admin helper | not approved | never | Open setup |

- App updates show as a count ("2 updates", links to Applications › Updates) but never change the status.
- The low-disk and Trash settings are the same values the menu bar alerts use (spec 011), so the low-disk notification fires the moment Health turns orange.
- Refresh: on app launch, when Health opens, after every run. No background scanning. "Junk found" is labelled with the date of the scan it came from.

## 2. Reminders

- Notification only; never unattended scanning or cleaning.
- Text: "Time to Tidy Up. Last run 16 days ago." Default action opens TidyMyMac on Tidy Up and **starts the scan** (scans delete nothing). Second action **Tomorrow** snoozes one day.
- Timing counts from the **last completed Tidy Up run**: due = last run + interval, at the chosen time of day. If ignored, one repeat 3 days later, then silent until the next Tidy Up run. Implemented as local `UNUserNotificationCenter` requests (calendar triggers), rescheduled on every Tidy Up completion, app launch and settings change; the app need not be running. A Mac asleep at the time gets it on wake.
- Never run: due = first launch + interval.
- Defaults: **on**, **every 2 weeks**, **10:00**. Choices: every week / every 2 weeks / every month. (Replaces the prototype's "Every week".)
- Permission: macOS's notification prompt is requested only on the Done screen of the first Tidy Up ("Remind me to run Tidy Up every 2 weeks?"). If denied, the Reminders card shows "Notifications are off in System Settings" with a link.

## 3. Settings

- Reminders on/off, how often, time of day. Shown on the Reminders card in Health and repeated in Settings (⌘,).
- Low-disk and Trash lines are the shared menu bar alert settings. The other thresholds above are fixed in v1.
