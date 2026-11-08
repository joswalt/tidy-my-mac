#!/bin/bash
# The release gate (docs/release-checklist.md, spec 017 §6) as one script. Run it on `main` after the
# release PR (version bump + docs/releases/vX.Y.Z.md) is merged:
#   scripts/release-gate.sh
#   scripts/release-gate.sh --from canaries   after a stop in the canary steps: keeps the report of
#                                             steps 1–4 and starts again at the canaries (allowed
#                                             only when nothing but scripts/ or docs/ changed since)
# It runs every check it can, stops only for the steps that need you in the app, writes the
# filled-in checklist to build/release-gate-vX.Y.Z.md, then asks once before it tags, pushes the tag
# and creates the GitHub Release (answer N to only print the commands). Any FAIL stops the gate.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=/Applications/TidyMyMac.app
BUILT=build/DerivedData/Build/Products/Release/TidyMyMac.app

version=$(sed -n 's/^MARKETING_VERSION *= *//p' Config/Shared.xcconfig)
build=$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' Config/Shared.xcconfig)
tag="v$version"
REPORT="build/release-gate-$tag.md"
mkdir -p build

say()  { printf '\n\033[1m== %s\033[0m\n' "$1"; }
line() { echo "$1" >> "$REPORT"; }
pass() { echo "PASS $1"; line "- [x] $1"; }
fail() { echo "FAIL $1"; line "- [ ] FAIL: $1"; echo; echo "Gate stopped. Report so far: $REPORT"; [ "${full:-}" = yes ] && echo "After a fix to the canary steps: scripts/release-gate.sh --from canaries"; exit 1; }
pause() { echo; echo "$1"; read -r -p "Press Return when done… " _; }
# yes/no/skip question for a manual step; a skip needs a reason and is recorded.
ask() {
  local a why
  while true; do
    read -r -p "$1 [y = yes, n = no, s = skip] " a
    case "$a" in
      y|Y) pass "$1"; return 0 ;;
      n|N) fail "$1" ;;
      s|S) read -r -p "Why skip? " why; echo "SKIP $1"; line "- Skipped: $1 ($why)"; return 0 ;;
    esac
  done
}
relaunch() { # extra app arguments
  osascript -e 'tell application "TidyMyMac" to quit' >/dev/null 2>&1 || true
  sleep 2
  open -a "$APP" --args "$@"
}

FROM=all
if [ "${1:-}" = --from ] && [ "${2:-}" = canaries ]; then FROM=canaries
elif [ -n "${1:-}" ]; then echo "usage: $0 [--from canaries]" >&2; exit 2; fi

say "Release $tag (build $build)"
git fetch -q origin main --tags
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Check out main first."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "The working tree isn't clean."; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main isn't at origin/main; pull first."; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "Tag $tag already exists: bump MARKETING_VERSION."; exit 1; }
[ -f "docs/releases/$tag.md" ] || { echo "docs/releases/$tag.md is missing (the release notes)."; exit 1; }
last=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
commit=$(git rev-parse --short HEAD)

if [ $FROM = canaries ]; then
  [ -f "$REPORT" ] || { echo "No earlier report ($REPORT) to resume from."; exit 1; }
  # The earlier run's report must say steps 1-4 passed: copy it up to the canary section.
  grep -q "check-local.sh: tests" "$REPORT" || { echo "The earlier report doesn't show check-local.sh passing; run the whole gate."; exit 1; }
  was=$(sed -n 's/^| Commit | `\(.*\)` |$/\1/p' "$REPORT")
  changed=$(git diff --name-only "$was..HEAD" | grep -vE '^(scripts|docs)/' || true)
  [ -z "$changed" ] || { echo "Files besides scripts/ and docs/ changed since $was; run the whole gate:"; echo "$changed"; exit 1; }
  sed -i '' '/^## Full form/,$d' "$REPORT"
  sed -i '' "s/^| Commit | .*/| Commit | \`$commit\` (steps 1–4 on \`$was\`; only scripts and docs changed since) |/" "$REPORT"
else
{ echo "# Release gate: $tag"; echo
  echo "| | |"; echo "|---|---|"
  echo "| Version | $version (build $build) |"; echo "| Commit | \`$commit\` |"
  echo "| Date | $(date +%Y-%m-%d) |"; echo "| Previous | ${last:-none} |"; echo; } > "$REPORT"
fi

if [ -n "$last" ]; then
  last_build=$(git show "$last:Config/Shared.xcconfig" | sed -n 's/^CURRENT_PROJECT_VERSION *= *//p')
  [ "$build" -gt "$last_build" ] || { echo "Build $build isn't above $last's build $last_build: the installed helper wouldn't be replaced."; exit 1; }
  full_paths=(Packages/TidyCore/Sources/SafetyFloor Packages/TidyCore/Sources/HelperCore Helper Packages/TidyCore/Sources/RuleEngine Rules)
  account_paths=(Packages/TidyCore/Sources/SafetyFloor Packages/TidyCore/Sources/HelperCore Helper)
  full=$([ -n "$(git diff --name-only "$last..HEAD" -- "${full_paths[@]}")" ] && echo yes || echo no)
  account=$([ -n "$(git diff --name-only "$last..HEAD" -- "${account_paths[@]}")" ] && echo yes || echo no)
else
  full=yes; account=yes
fi
echo "Full form: $full (SafetyFloor, HelperCore, Helper, RuleEngine or Rules changed since ${last:-the start})"
echo "Temporary tidytest account: $account (SafetyFloor, HelperCore or Helper changed)"
[ $FROM = canaries ] || { line "Form: $([ $full = yes ] && echo full || echo short). Temporary tidytest account: $account."; line ""; }
[ $FROM = canaries ] && [ $full = no ] && { echo "This release uses the short form; there are no canary steps."; exit 1; }

if [ $FROM = all ]; then

line "## Short form"
say "1. CI on $commit"
if command -v gh >/dev/null; then
  run=$(gh run list --workflow CI --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId,conclusion --jq '.[] | "\(.databaseId) \(.conclusion)"' 2>/dev/null || true)
  if [ -z "$run" ]; then
    echo "No CI run on this commit yet; starting one."
    gh workflow run CI --ref main
    sleep 10
    run=$(gh run list --workflow CI --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId,conclusion --jq '.[] | "\(.databaseId) \(.conclusion)"')
    [ -n "$run" ] || fail "couldn't start a CI run on $commit"
  fi
  id=${run%% *}
  gh run watch "$id" --exit-status >/dev/null && pass "CI green on $commit (run $id)" || fail "CI on $commit (run $id)"
else
  ask "CI is green on $commit (no gh here, check GitHub)"
fi

say "2. check-local.sh"
scripts/check-local.sh && pass "check-local.sh: tests, lints, signed Release build, codesign, helper plist" || fail "check-local.sh"

say "4. Install over the previous build"
osascript -e 'tell application "TidyMyMac" to quit' >/dev/null 2>&1 || true
sleep 2
rm -rf "$APP"
ditto "$BUILT" "$APP"
open "$APP"
pass "Installed $commit in $APP"
ask "The helper restarted with no new approval prompt, and Health › Run History still has the old runs"

say "3. Click-through and 3a. accessibility (see docs/release-checklist.md)"
ask "Click-through: first-run sheet, every module, My Tools, Tidy Up dry run, menu bar, Settings, keyboard"
ask "Accessibility: VoiceOver, Reduce Motion, Increase Contrast, Full Keyboard Access"
fi

if [ $full = yes ]; then
  line ""; line "## Full form"
  say "5–6. Canary runs (user and helper)"
  scripts/user-canary.sh setup
  sudo scripts/canary.sh setup
  relaunch -TidyCanaryRun YES
  pause "In TidyMyMac (opened in canary mode): Cleanup › Scan. Only TidyCanary items start ticked
(in your Library and, with the helper, in /Library). Leave TidyKeep items alone.
Then Clean (enter your password for the helper)."
  sudo scripts/canary.sh check && pass "Helper canaries: only the ticked ones removed" || fail "sudo scripts/canary.sh check"
  pause "Health › Run History › that run › Restore the 'io.github.joswalt.TidyCanary.Agent.plist' item (not Restore All)."
  sudo scripts/canary.sh check-restored && pass "Helper restore: same file, root:wheel, 644" || fail "sudo scripts/canary.sh check-restored"
  sudo scripts/canary.sh cleanup
  pause "Applications › Uninstaller: uninstall 'TidyCanary Dummy'.
Then Cleanup › Scan Again: only the TidyCanary items in the Trash are ticked. Clean."
  scripts/user-canary.sh check && pass "User canaries: only canaries removed, Trash emptied, TidyKeep items unchanged" || fail "scripts/user-canary.sh check"
  scripts/user-canary.sh cleanup
  relaunch

  if [ $account = yes ]; then
    say "5a. Temporary tidytest account"
    sudo scripts/tidytest-account.sh create
    pause "Do the tidytest run now (steps printed above), then switch back here."
    if sudo -u tidytest -H /Users/Shared/TidyTest/verify-tidytest.sh; then pass "tidytest real run: verify-tidytest.sh PASS"
    else sudo scripts/tidytest-account.sh delete; fail "verify-tidytest.sh"; fi
    sudo scripts/tidytest-account.sh delete
    pass "tidytest account deleted"
  fi

  say "7. Experimental rules"
  ask "Dry run of every experimental rule on your account looks right (Cleanup: tick their items, Dry Run)"
  say "8. Live update check"
  ask "Applications › Updates matches each app's own Check for Updates for 5 apps"
fi

line ""; line "RESULT: PASS"
say "Gate passed: $REPORT"
sha=$(git rev-parse HEAD)
publish=(
  "git tag -a $tag -F $REPORT $sha"
  "git push origin $tag"
  "gh release create $tag --title \"TidyMyMac $version\" --notes-file docs/releases/$tag.md --latest"
)
echo; echo "Tag and publish:"; printf '  %s\n' "${publish[@]}"
echo
echo "A pushed tag is public and is never moved; a mistake means a new version."
read -r -p "Tag $sha as $tag and publish the Release now? [y/N] " a
if [ "$a" = y ] || [ "$a" = Y ]; then
  git tag -a "$tag" -F "$REPORT" "$sha"
  git push origin "$tag"
  if command -v gh >/dev/null; then
    gh release create "$tag" --title "TidyMyMac $version" --notes-file "docs/releases/$tag.md" --latest
    echo "Published $tag."
  else
    echo "Tagged and pushed $tag. gh isn't installed: create the Release on GitHub from docs/releases/$tag.md."
  fi
else
  echo "Not published. Run the commands above when you're ready."
fi
