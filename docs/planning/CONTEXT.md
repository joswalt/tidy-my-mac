# TidyMyMac glossary

- **Feature**: one user-visible capability (e.g. Uninstaller, Space Lens), as listed in the feature catalogue.
- **Module**: a group of related features shown as one section of the app (Cleanup, Performance, Applications...).
- **Safety rule**: a statement that a given kind of item (path pattern, file type) may be removed, and how (Trash or delete).
- **Admin helper**: the separate component that performs actions requiring administrator rights on behalf of the app.
- **Clean-room**: building from public documentation and observed behaviour only, never from CleanMyMac's code or data.
- **Risk level**: how a safety rule's items are offered: safe (ticked), caution (unticked), risky (never in Smart Care, ticked one by one).
- **Protected floor**: paths built into the app's code that no rule or user choice can remove.
- **Zone**: a fixed folder the admin helper may act on, with its own delete-or-Trash action (spec 005).
- **Monitor**: a live reading in the menu bar popover (CPU, Memory, Storage, Network), sampled only while the popover is open (spec 011).
- **Alert**: a notification fired once when a watched value crosses its threshold (low disk, full Trash); it re-arms after recovery or 24 h (spec 011).
- **Low-disk setting**: the one free-space threshold shared by the low disk alert and Health's orange line.
- **Health status**: the overall state shown in Health (Looks good / Worth a look / Needs attention), equal to its worst signal (spec 012).
- **Signal**: one checked condition feeding the health status, with its own state and fix button.
- **Reminder**: a scheduled notification nudging John to run Smart Care, counted from the last run; never cleans by itself.
