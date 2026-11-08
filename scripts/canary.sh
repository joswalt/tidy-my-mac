#!/bin/bash
# Canary files for the real-helper check (spec 017 §4.3). Run with sudo.
#   sudo scripts/canary.sh setup   creates root-owned canaries in the helper's zones
#   sudo scripts/canary.sh check   after the run: which canaries are gone, and whether anything
#                                   else in those zones changed. Exits 1 (RESULT: FAIL) when a ticked
#                                   canary is still there, the B canary is gone, or any other entry
#                                   listed at setup is gone.
#   sudo scripts/canary.sh check-restored   after `check` passed and the Dummy agent was restored in
#                                   TidyMyMac: it is back as the same file (same inode), a regular file,
#                                   owned root:wheel, mode 644.
#   CANARY_ROOT=<temp dir>          tests only (scripts/test-scripts.sh): run inside a fake root, no sudo
set -euo pipefail
R="${CANARY_ROOT:-}"
[ -n "$R" ] || [ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
STAMP_FILE=$R/var/root/.tidy-canary-stamp
DUMMY=$R/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist
DUMMY_INODE=$R/var/root/.tidy-canary-dummy-inode
LIST=$R/var/root/.tidy-canary-zones.txt
ZONES=("$R/Library/Caches" "$R/Library/Logs" "$R/Library/LaunchAgents")
case "${1:-}" in
setup)
  d=$(date +%Y%m%d)
  echo "$d" > "$STAMP_FILE"
  mkdir -p "$R/Library/Caches/TidyCanary-$d-A" "$R/Library/Caches/TidyCanary-$d-B" "$R/Library/Logs/TidyCanary-$d" "$R/Library/LaunchAgents"
  head -c 65536 /dev/urandom > "$R/Library/Caches/TidyCanary-$d-A/data"
  head -c 65536 /dev/urandom > "$R/Library/Caches/TidyCanary-$d-B/data"
  echo "canary log" > "$R/Library/Logs/TidyCanary-$d/canary.log"
  rm -f "$R/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist"
  /usr/libexec/PlistBuddy -c "Add :Label string io.github.joswalt.TidyTest.Dummy" \
    -c "Add :Program string /Library/TidyTest/missing-program" "$R/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist" >/dev/null
  stat -f %i "$DUMMY" > "$DUMMY_INODE"
  : > "$LIST"
  for z in "${ZONES[@]}"; do ls -1A "$z" | sed "s|^|$z/|" >> "$LIST"; done
  echo "Canaries created (tick only TidyCanary-$d-A, the TidyCanary log folder and the TidyTest Dummy agent):"
  ls -d "$R"/Library/Caches/TidyCanary-* "$R"/Library/Logs/TidyCanary-* "$R"/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist
  ;;
check)
  d=$(cat "$STAMP_FILE")
  fail=0
  for p in "$R/Library/Caches/TidyCanary-$d-A" "$R/Library/Logs/TidyCanary-$d" "$R/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist"; do
    if [ -e "$p" ]; then echo "FAIL still there (was it ticked?): $p"; fail=1; else echo "PASS removed: $p"; fi
  done
  if [ -e "$R/Library/Caches/TidyCanary-$d-B/data" ]; then echo "PASS untouched: TidyCanary-$d-B"; else echo "FAIL removed without being ticked: TidyCanary-$d-B"; fail=1; fi
  while IFS= read -r p; do
    case "$p" in *TidyCanary-$d-A|*TidyCanary-$d|*TidyTest.Dummy.plist) continue;; esac
    # Some Apple folders are Data Vaults: even root can't stat them, so look them up in the listing.
    [ -e "$p" ] || ls -1A "$(dirname "$p")" 2>/dev/null | grep -qxF "$(basename "$p")" \
      || { echo "FAIL gone since setup (system churn or the run?): $p"; fail=1; }
  done < "$LIST"
  if [ $fail = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
  ;;
check-restored)
  # Run only after `check` passed and the Dummy agent was restored from TidyMyMac's history.
  want_uid=0; want_gid=0
  [ -n "$R" ] && { want_uid=$(id -u); want_gid=$(id -g); }  # tests: the fake root belongs to the user
  fail=0
  if [ -L "$DUMMY" ] || [ ! -f "$DUMMY" ]; then
    echo "FAIL not restored (missing or not a regular file): $DUMMY"; fail=1
  else
    read -r ino uid gid mode < <(stat -f '%i %u %g %Lp' "$DUMMY")
    [ "$ino" = "$(cat "$DUMMY_INODE" 2>/dev/null)" ] && echo "PASS same file as at setup (inode $ino)" \
      || { echo "FAIL a different file came back (inode $ino)"; fail=1; }
    [ "$uid:$gid" = "$want_uid:$want_gid" ] && echo "PASS owner $uid:$gid" || { echo "FAIL owner $uid:$gid, expected $want_uid:$want_gid"; fail=1; }
    [ "$mode" = 644 ] && echo "PASS mode 644" || { echo "FAIL mode $mode, expected 644"; fail=1; }
  fi
  if [ $fail = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
  ;;
*) echo "usage: sudo $0 setup|check|check-restored" >&2; exit 2 ;;
esac
