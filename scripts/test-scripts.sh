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
TICKED='rm -rf "Library/Caches/TidyCanary-$D-A" "Library/Logs/TidyCanary-$D" Library/LaunchAgents/io.github.joswalt.TidyCanary.Agent.plist'
run_case "only ticked canaries removed passes" 0 PASS "$TICKED"
run_case "ticked canary still there fails" 1 FAIL 'rm -rf "Library/Logs/TidyCanary-$D" Library/LaunchAgents/io.github.joswalt.TidyCanary.Agent.plist'
run_case "unticked canary removed fails" 1 FAIL "$TICKED; rm -rf \"Library/Caches/TidyKeep-\$D-B\""
run_case "other zone entry gone fails" 1 FAIL "$TICKED; rm -rf Library/Caches/Other"

# canary.sh check-restored: the Dummy agent back as the same file, owner and mode.
restored_case() { # name, expected exit, mutation (run in the fake root, D = stamp)
  local name=$1 want=$2 mutate=$3 root code out
  root=$(mktemp -d)
  mkdir -p "$root/var/root" "$root/Library/Caches" "$root/Library/Logs" "$root/Library/LaunchAgents"
  CANARY_ROOT=$root scripts/canary.sh setup >/dev/null
  chmod 644 "$root/Library/LaunchAgents/io.github.joswalt.TidyCanary.Agent.plist"
  (cd "$root" && P=Library/LaunchAgents/io.github.joswalt.TidyCanary.Agent.plist eval "$mutate")
  out=$(CANARY_ROOT=$root scripts/canary.sh check-restored 2>&1); code=$?
  rm -rf "$root"
  if [ "$code" = "$want" ]; then ok "canary restored: $name"; else bad "canary restored: $name (exit $code)"; echo "$out" | sed 's/^/     /'; fi
}
restored_case "moved out and back passes" 0 'mv "$P" moved.plist && mv moved.plist "$P"'
restored_case "missing fails" 1 'rm "$P"'
restored_case "a different file fails" 1 'cp "$P" new.plist && rm "$P" && mv new.plist "$P" && chmod 644 "$P"'
restored_case "wrong mode fails" 1 'chmod 666 "$P"'
restored_case "a symlink fails" 1 'mv "$P" real.plist && ln -s "$PWD/real.plist" "$P"'

# user-canary.sh check: run logs may only name canaries; canaries gone; TidyKeep items unchanged.
# Each case is a function run in the fake home with H (its path) and D (the setup stamp) set.
uc_log() { # a real-run log removing every setup canary, plus any extra paths given
  { echo '{"type":"header","module":"cleanup","dryRun":false}'
    { cat "$H/.tidy-user-canary/canaries"; [ $# = 0 ] || printf '%s\n' "$@"; } | while IFS= read -r p; do
      printf '{"type":"item","path":"%s","action":"delete","result":"done"}\n' "$p"; done
    echo '{"type":"summary"}'; } > "$H/Library/Application Support/TidyMyMac/RunLog/run.jsonl"
}
uc_rm()    { while IFS= read -r p; do rm -rf "$p"; done < "$H/.tidy-user-canary/canaries"; }
uc_pass()  { uc_log; uc_rm; }
uc_extra() { uc_log "$H/Library/Caches/com.example.Real"; uc_rm; }
uc_left()  { uc_log; }
uc_keep()  { uc_log; uc_rm; echo x >> "$H/TidyKeep-$D/symlinked.txt"; }
uc_none()  { :; }
user_case() { # name, expected exit, case function
  local name=$1 want=$2 fn=$3 h d out code
  h=$(mktemp -d)
  HOME=$h scripts/user-canary.sh setup >/dev/null
  d=$(cat "$h/.tidy-user-canary/stamp")
  mkdir -p "$h/Library/Application Support/TidyMyMac/RunLog"
  H=$h D=$d "$fn"
  out=$(HOME=$h scripts/user-canary.sh check 2>&1); code=$?
  rm -rf "$h"
  if [ "$code" = "$want" ]; then ok "user canary: $name"; else bad "user canary: $name (exit $code)"; echo "$out" | sed 's/^/     /'; fi
}
user_case "only canaries removed passes" 0 uc_pass
user_case "a non-canary in the run log fails" 1 uc_extra
user_case "a canary left behind fails" 1 uc_left
user_case "a changed TidyKeep file fails" 1 uc_keep
user_case "no real run fails" 1 uc_none

[ $failures = 0 ] && echo "All script tests passed." || { echo "$failures script test(s) failed."; exit 1; }
