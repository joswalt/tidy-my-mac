#!/bin/bash
# Regression tests for the repo's tooling: CI hardening and canary.sh check failing loudly.
# Runs without sudo; canary.sh runs inside a temp fake root (CANARY_ROOT).
set -uo pipefail
cd "$(dirname "$0")/.."
failures=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; failures=$((failures + 1)); }

# CI workflow hardening.
ci=.github/workflows/ci.yml
grep -qE '^permissions:' "$ci" && grep -A1 -E '^permissions:' "$ci" | grep -qE '^\s+contents: read' \
  && ok "ci: top-level permissions contents: read" || bad "ci: top-level permissions contents: read"
if grep -E 'uses: [^ ]+@' "$ci" | grep -vqE '@[0-9a-f]{40}( |$)'; then bad "ci: every action pinned to a full commit SHA"; else ok "ci: every action pinned to a full commit SHA"; fi
grep -A2 'uses: actions/checkout@' "$ci" | grep -qE 'persist-credentials: false' \
  && ok "ci: checkout persist-credentials false" || bad "ci: checkout persist-credentials false"

# canary.sh check: exit status and RESULT line for each outcome.
run_case() { # name, expected exit, expected RESULT, mutation
  local name=$1 want=$2 result=$3 mutate=$4 root out code
  root=$(mktemp -d)
  mkdir -p "$root/var/root" "$root/Library/Caches/Other" "$root/Library/Logs" "$root/Library/LaunchAgents"
  CANARY_ROOT=$root scripts/canary.sh setup >/dev/null
  d=$(cat "$root/var/root/.tidy-canary-stamp")
  (cd "$root" && D=$d eval "$mutate")
  out=$(CANARY_ROOT=$root scripts/canary.sh check 2>&1); code=$?
  rm -rf "$root"
  if [ "$code" = "$want" ] && echo "$out" | grep -qx "RESULT: $result"; then ok "canary: $name"; else bad "canary: $name (exit $code)"; echo "$out" | sed 's/^/     /'; fi
}
TICKED='rm -rf "Library/Caches/TidyCanary-$D-A" "Library/Logs/TidyCanary-$D" Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist'
run_case "only ticked canaries removed passes" 0 PASS "$TICKED"
run_case "ticked canary still there fails" 1 FAIL 'rm -rf "Library/Logs/TidyCanary-$D" Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist'
run_case "unticked canary removed fails" 1 FAIL "$TICKED; rm -rf \"Library/Caches/TidyCanary-\$D-B\""
run_case "other zone entry gone fails" 1 FAIL "$TICKED; rm -rf Library/Caches/Other"

[ $failures = 0 ] && echo "All script tests passed." || { echo "$failures script test(s) failed."; exit 1; }
