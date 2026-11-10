#!/bin/bash
# Canary files for the real-helper check (spec 017 §4.3). Run with sudo.
#   sudo scripts/canary.sh setup   creates root-owned canaries in the helper's zones
#   sudo scripts/canary.sh check   after the run: which canaries are gone, and whether anything
#                                   else in those zones changed. Exits 1 (RESULT: FAIL) when a ticked
#                                   canary is still there, the B canary is gone, or any other entry
#                                   listed at setup is gone.
#   sudo scripts/canary.sh cleanup   at the very end: removes what is left (the restored canary agent,
#                                   the TidyKeep canary, the setup records).
#   sudo scripts/canary.sh check-restored   after `check` passed and the canary agent was restored in
#                                   TidyMyMac: it is back as the same file (same inode), a regular file,
#                                   owned root:wheel, mode 644.
#   CANARY_ROOT=<temp dir>          tests only (scripts/test-scripts.sh): run inside a fake root, no sudo
set -euo pipefail
R="${CANARY_ROOT:-}"
[ -n "$R" ] || [ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
STAMP_FILE=$R/var/root/.tidy-canary-stamp
DUMMY=$R/Library/LaunchAgents/io.github.joswalt.TidyCanary.Agent.plist
OLD_DUMMY=$R/Library/LaunchAgents/io.github.joswalt.TidyTest.Dummy.plist  # its name before 1.0.2
DUMMY_INODE=$R/var/root/.tidy-canary-dummy-inode
LIST=$R/var/root/.tidy-canary-zones.txt
ZONES=("$R/Library/Caches" "$R/Library/Logs" "$R/Library/LaunchAgents")
WANT_UID=0
[ -n "$R" ] && WANT_UID=$(id -u)  # tests: the fake root belongs to the user

# /Library/Caches is world-writable (1777) and the canary names are predictable, so another
# process could plant a folder or symlink there first and have root write through it. Make each
# canary folder fresh: refuse anything already there that isn't our own root-owned folder, remove
# an old one of ours, then mkdir without -p (fails if something appeared meanwhile) and check it.
fresh_dir() {
  local p=$1
  if [ -L "$p" ] || { [ -e "$p" ] && { [ ! -d "$p" ] || [ "$(stat -f %u "$p")" != "$WANT_UID" ]; }; }; then
    echo "Refusing: $p already exists and isn't a canary folder made by this script. Remove it, then run setup again." >&2
    exit 1
  fi
  rm -rf "$p"
  mkdir -m 755 "$p"
  [ ! -L "$p" ] && [ -d "$p" ] && [ "$(stat -f %u "$p")" = "$WANT_UID" ] \
    || { echo "Refusing: $p changed while it was being made." >&2; exit 1; }
}
case "${1:-}" in
setup)
  d=$(date +%Y%m%d)
  echo "$d" > "$STAMP_FILE"
  for p in "$R/Library/Caches/TidyCanary-$d-A" "$R/Library/Caches/TidyKeep-$d-B" "$R/Library/Logs/TidyCanary-$d"; do fresh_dir "$p"; done
  mkdir -p "$R/Library/LaunchAgents"
  head -c 65536 /dev/urandom > "$R/Library/Caches/TidyCanary-$d-A/data"
  head -c 65536 /dev/urandom > "$R/Library/Caches/TidyKeep-$d-B/data"
  echo "canary log" > "$R/Library/Logs/TidyCanary-$d/canary.log"
  rm -f "$DUMMY" "$OLD_DUMMY"
  /usr/libexec/PlistBuddy -c "Add :Label string io.github.joswalt.TidyCanary.Agent" \
    -c "Add :Program string /Library/TidyCanary/missing-program" "$DUMMY" >/dev/null
  stat -f %i "$DUMMY" > "$DUMMY_INODE"
  : > "$LIST"
  for z in "${ZONES[@]}"; do ls -1A "$z" | sed "s|^|$z/|" >> "$LIST"; done
  echo "Canaries created. Tick every TidyCanary item (canary mode does); leave TidyKeep-$d-B:"
  ls -d "$R"/Library/Caches/TidyCanary-* "$R"/Library/Caches/TidyKeep-* "$R"/Library/Logs/TidyCanary-* "$DUMMY"
  ;;
check)
  d=$(cat "$STAMP_FILE")
  fail=0
  for p in "$R/Library/Caches/TidyCanary-$d-A" "$R/Library/Logs/TidyCanary-$d" "$DUMMY"; do
    if [ -e "$p" ]; then echo "FAIL still there (was it ticked?): $p"; fail=1; else echo "PASS removed: $p"; fi
  done
  if [ -e "$R/Library/Caches/TidyKeep-$d-B/data" ]; then echo "PASS untouched: TidyKeep-$d-B"; else echo "FAIL removed without being ticked: TidyKeep-$d-B"; fail=1; fi
  while IFS= read -r p; do
    case "$p" in *TidyCanary-$d-A|*TidyCanary-$d|*TidyCanary.Agent.plist) continue;; esac
    # Some Apple folders are Data Vaults: even root can't stat them, so look them up in the listing.
    [ -e "$p" ] || ls -1A "$(dirname "$p")" 2>/dev/null | grep -qxF "$(basename "$p")" \
      || { echo "FAIL gone since setup (system churn or the run?): $p"; fail=1; }
  done < "$LIST"
  if [ $fail = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
  ;;
check-restored)
  # Run only after `check` passed and the canary agent was restored from TidyMyMac's history.
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
cleanup)
  d=$(cat "$STAMP_FILE" 2>/dev/null || true)
  rm -f "$DUMMY" "$OLD_DUMMY"
  [ -n "$d" ] && rm -rf "$R/Library/Caches/TidyKeep-$d-B" "$R/Library/Caches/TidyCanary-$d-A" "$R/Library/Logs/TidyCanary-$d"
  rm -f "$STAMP_FILE" "$DUMMY_INODE" "$LIST"
  echo "Canaries cleaned up."
  ;;
*) echo "usage: sudo $0 setup|check|check-restored|cleanup" >&2; exit 2 ;;
esac
