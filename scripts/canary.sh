#!/bin/bash
# Canary files for the real-helper check (spec 017 §4.3). Run with sudo.
#   sudo scripts/canary.sh setup   creates root-owned canaries in the helper's zones
#   sudo scripts/canary.sh check   after the run: which canaries are gone, and whether anything
#                                   else in those zones changed
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
STAMP_FILE=/var/root/.tidy-canary-stamp
LIST=/var/root/.tidy-canary-zones.txt
ZONES=(/Library/Caches /Library/Logs /Library/LaunchAgents)
case "${1:-}" in
setup)
  d=$(date +%Y%m%d)
  echo "$d" > "$STAMP_FILE"
  mkdir -p "/Library/Caches/TidyCanary-$d-A" "/Library/Caches/TidyCanary-$d-B" "/Library/Logs/TidyCanary-$d"
  head -c 65536 /dev/urandom > "/Library/Caches/TidyCanary-$d-A/data"
  head -c 65536 /dev/urandom > "/Library/Caches/TidyCanary-$d-B/data"
  echo "canary log" > "/Library/Logs/TidyCanary-$d/canary.log"
  rm -f "/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist"
  /usr/libexec/PlistBuddy -c "Add :Label string io.github.joswalt.TidyTest.Dummy" \
    -c "Add :Program string /Library/TidyTest/missing-program" "/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist" >/dev/null
  : > "$LIST"
  for z in "${ZONES[@]}"; do ls -1A "$z" | sed "s|^|$z/|" >> "$LIST"; done
  echo "Canaries created (tick only TidyCanary-$d-A, the TidyCanary log folder and the TidyTest Dummy agent):"
  ls -d /Library/Caches/TidyCanary-* /Library/Logs/TidyCanary-* /Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist
  ;;
check)
  d=$(cat "$STAMP_FILE")
  fail=0
  for p in "/Library/Caches/TidyCanary-$d-A" "/Library/Logs/TidyCanary-$d" "/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist"; do
    if [ -e "$p" ]; then echo "STILL THERE (was it ticked?): $p"; else echo "PASS removed: $p"; fi
  done
  if [ -e "/Library/Caches/TidyCanary-$d-B/data" ]; then echo "PASS untouched: TidyCanary-$d-B"; else echo "FAIL removed without being ticked: TidyCanary-$d-B"; fail=1; fi
  while IFS= read -r p; do
    case "$p" in *TidyCanary-$d-A|*TidyCanary-$d|*TidyTest.Dummy.plist) continue;; esac
    # Some Apple folders are Data Vaults: even root can't stat them, so look them up in the listing.
    [ -e "$p" ] || ls -1A "$(dirname "$p")" 2>/dev/null | grep -qxF "$(basename "$p")" \
      || echo "CHECK gone since setup (system churn or the run?): $p"
  done < "$LIST"
  [ $fail = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
  ;;
*) echo "usage: sudo $0 setup|check" >&2; exit 2 ;;
esac
