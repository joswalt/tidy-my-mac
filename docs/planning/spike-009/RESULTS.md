# Spike 009 results (2026-11-07, John's Mac)

Environment: macOS 26.7.1 (25G241), Apple Silicon, Swift 6.4.2. Identity: free Personal Team "Apple Development" (team OU 26TUUFN7M2). Sources compiled unchanged (built with swiftc + codesign, no Xcode project).

## Setup gotcha
A fresh Personal Team certificate showed as "not valid" and codesign failed with `errSecInternalComponent` ("unable to build chain to self-signed root") because the keychain only had the WWDR intermediate that expired in 2023. Fix: import Apple's public `AppleWWDRCAG3.cer` (https://www.apple.com/certificateauthority/) into the login keychain. The builder's setup docs must include this check.

## Steps and outputs
| Step | Result |
|---|---|
| `register` | threw "Operation not permitted" (code 1), status `requiresApproval` (expected) |
| John approves in Login Items | status `enabled` |
| XPC `call` | `uid=0 euid=0`, wrote root-owned `/Library/Application Support/TidyMyMacSpike/proof.txt` |
| FDA probe, no FDA | DENIED (257) on `/Library/Application Support/com.apple.TCC` |
| Add only `TidySpike.app` to Full Disk Access, unregister+register | no re-approval prompt; FDA probe readable |
| Rebuild with same identity, copy over installed app | status stays `enabled`; old helper process keeps answering until restarted; after unregister+register the new binary runs as uid 0, FDA still granted, no re-approval |
| `networksetup -listpreferredwirelessnetworks en0` as root | exit 0, SSID list returned (no Location Services needed) |
| Ad hoc build over the top | status still says `enabled`, but launchd refuses to spawn: `spawn failed, last exit code = 78: EX_CONFIG`; XPC times out |

## Answers
- Personal Team signing + SMAppService.daemon register/approve: **yes**.
- Root over XPC with code-signing requirement (identifier + anchor apple generic + team OU): **yes**.
- Survives rebuild with the same identity: **yes**, no re-approval; but the running helper must be restarted to pick up a new binary.
- Helper needs Full Disk Access added by hand (spec 005 Q2): **no**, it inherits from the app's FDA entry.
- Wi-Fi SSIDs as root without Location Services (Q4): **yes**.
- Certificate lifetime (Q6): **1 year** (Nov 7 2026 to Nov 7 2027). Whether a renewed cert forces re-approval is untested (same Team ID, so likely not).
- Ad hoc signing: **does not work** on macOS 26 (launchd EX_CONFIG while status misleadingly says enabled). Spec 005 Plan B is dead; Plan C (osascript one-shot) is the only fallback.

Cleanup: daemon unregistered, app deleted. John removes the FDA entry and runs `sudo rm -rf "/Library/Application Support/TidyMyMacSpike"`. Sources remain at `~/tidymymac-spike-009` on his Mac.
