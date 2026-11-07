---
id: 002
title: Installing an admin helper without a paid developer account
type: wayfinder:research
status: closed
assignee: claude-research
blocked_by: []
---

## Question

On macOS 14+ Apple Silicon, with no paid Apple Developer account, what are the workable ways to run privileged operations from a personal SwiftUI app (SMAppService daemon with ad-hoc / free Personal Team signing, legacy SMJobBless, AuthorizationExecuteWithPrivileges, osascript "with administrator privileges", sudo shell helper)? For each: does it work, what prompts the user sees, Gatekeeper/notarization implications, and how it would change if we later buy an account.

## Resolution

Findings: [research/002-helper-without-dev-account.md](../research/002-helper-without-dev-account.md).
Use SMAppService.daemon + small XPC helper with a fixed operation allow-list and caller code-signature checks, signed with the free Personal Team identity (not "Sign to Run Locally"). Unconfirmed by Apple that Personal Team signing works for daemons → proven in ticket 009. osascript "with administrator privileges" only as a rare fallback. Avoid SMJobBless, AuthorizationExecuteWithPrivileges, sudoers, hand-installed daemons. Paying $99 later only changes signing identity/notarization, not the design.
