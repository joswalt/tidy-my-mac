#!/bin/bash
# User-level canaries for the release gate's real run in John's own account (spec 017 §4.4).
# Run as yourself, not with sudo. Only items this script makes may be removed:
#   scripts/user-canary.sh setup     makes TidyCanary-<date> items (ticked by TidyMyMac's canary run)
#                                    and TidyKeep-<date> items (must survive), and records them
#   scripts/user-canary.sh check     after the runs: every item the run logs since setup say was
#                                    removed is a canary; every canary is gone (Trash emptied too);
#                                    every TidyKeep item is unchanged. Ends RESULT: PASS or FAIL (exit 1).
#   scripts/user-canary.sh cleanup   removes what setup left behind (TidyKeep items, records)
# The canary run: open TidyMyMac with `--args -TidyCanaryRun YES`, so scans tick only TidyCanary items.
# Tests (scripts/test-scripts.sh) run it with HOME set to a temp folder.
set -euo pipefail
[ "$(id -u)" != 0 ] || { echo "Run as yourself, not with sudo." >&2; exit 1; }
STATE="$HOME/.tidy-user-canary"
APP_ID=io.github.joswalt.TidyCanary.Dummy

mkfile() { mkdir -p "$(dirname "$1")"; head -c "${2:-4096}" /dev/urandom > "$1"; }

case "${1:-}" in
setup)
  d=$(date +%Y%m%d)
  rm -rf "$STATE"; mkdir -p "$STATE"
  KEEP="$HOME/TidyKeep-$d"
  # Tripwires a canary links to: deleting the canary must not touch them.
  mkfile "$KEEP/symlinked.txt" 8192
  mkfile "$KEEP/hardlinked.txt" 8192
  mkfile "$HOME/Library/Caches/TidyKeep-$d-B/data" 65536
  # App caches, User logs, Broken login items.
  C="$HOME/Library/Caches/TidyCanary-$d-A"
  mkfile "$C/data" 65536
  ln -sfn "$KEEP/symlinked.txt" "$C/link-to-keep"
  ln -f "$KEEP/hardlinked.txt" "$C/hardlink-to-keep"
  mkfile "$HOME/Library/Logs/TidyCanary-$d/canary.log" 2048
  mkdir -p "$HOME/Library/LaunchAgents"
  AGENT="$HOME/Library/LaunchAgents/io.github.joswalt.TidyCanary-$d.plist"
  rm -f "$AGENT"
  /usr/libexec/PlistBuddy -c "Add :Label string io.github.joswalt.TidyCanary-$d" \
    -c "Add :Program string $HOME/TidyCanary-missing-program" "$AGENT" >/dev/null
  # A dummy app for the Uninstaller, with two leftovers.
  APP="$HOME/Applications/TidyCanary Dummy.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/Dummy"; chmod 755 "$APP/Contents/MacOS/Dummy"
  for kv in "CFBundleIdentifier string $APP_ID" "CFBundleName string TidyCanary Dummy" "CFBundleExecutable string Dummy" \
            "CFBundlePackageType string APPL" "CFBundleShortVersionString string 1.0" "CFBundleVersion string 1"; do
    /usr/libexec/PlistBuddy -c "Add :$kv" "$APP/Contents/Info.plist" >/dev/null
  done
  mkfile "$HOME/Library/Application Support/$APP_ID/data.db"
  mkfile "$HOME/Library/Preferences/$APP_ID.plist" 512

  echo "$d" > "$STATE/stamp"
  printf '%s\n' "$C" "$HOME/Library/Logs/TidyCanary-$d" "$AGENT" "$APP" \
    "$HOME/Library/Application Support/$APP_ID" "$HOME/Library/Preferences/$APP_ID.plist" > "$STATE/canaries"
  for f in "$KEEP/symlinked.txt" "$KEEP/hardlinked.txt" "$HOME/Library/Caches/TidyKeep-$d-B/data"; do
    printf '%s\t%s\t%s\n' "$f" "$(stat -f %i "$f")" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
  done > "$STATE/keep"
  echo "User canaries created (TidyCanary-$d: a cache, a log folder, a broken login item, 'TidyCanary Dummy' in ~/Applications)."
  ;;
check)
  [ -f "$STATE/stamp" ] || { echo "No setup found; run setup first." >&2; exit 1; }
  exec /usr/bin/env python3 -I - "$HOME" "$STATE" <<'PY'
import hashlib, json, os, pathlib, sys
home, state = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
since = (state / "stamp").stat().st_mtime
fails = 0
def report(ok, msg):
    global fails
    fails += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + msg)

# Canary names (canary.sh's root canaries in the same run are named TidyCanary too).
def is_canary(p): return "TidyCanary" in os.path.basename(p.rstrip("/"))

runs = []
for f in sorted((home / "Library/Application Support/TidyMyMac/RunLog").glob("*.jsonl")):
    if f.stat().st_mtime < since: continue
    lines = []
    for l in f.read_text().splitlines():
        try: lines.append(json.loads(l))
        except ValueError: pass
    if lines and lines[0].get("type") == "header" and not lines[0].get("dryRun"):
        runs.append((f, lines))
report(bool(runs), f"{len(runs)} real run(s) since setup")
for f, lines in runs:
    items = [l for l in lines if l.get("type") == "item"]
    print(f"     {f.name} ({lines[0].get('module')}): {len(items)} item(s)")
    if not lines or lines[-1].get("type") != "summary":
        report(False, f"{f.name} has no summary line (interrupted)")
    for i in items:
        p = i.get("path", "")
        if not p: continue  # operations such as flushDNS
        if not is_canary(p):
            report(False, f"{i.get('result')} on something that isn't a canary: {p}")
        elif i.get("result") != "done":
            report(False, f"canary {i.get('result')}: {p} ({i.get('reason')})")

for p in (state / "canaries").read_text().splitlines():
    report(not os.path.lexists(p), f"gone: {p}")
trash = home / ".Trash"
try:
    left = [n for n in os.listdir(trash) if "TidyCanary" in n]
    report(not left, "no canaries left in the Trash" + (f" ({', '.join(left)})" if left else ""))
except FileNotFoundError:
    pass
except PermissionError:
    print("NOTE can't read ~/.Trash (give your terminal Full Disk Access to check it was emptied)")

for line in (state / "keep").read_text().splitlines():
    p, inode, digest = line.split("\t")
    if not os.path.isfile(p) or os.path.islink(p):
        report(False, f"TidyKeep item missing: {p}"); continue
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    report(str(os.lstat(p).st_ino) == inode and h == digest, f"unchanged: {p}")

print("RESULT: PASS" if not fails else f"RESULT: FAIL ({fails})")
sys.exit(1 if fails else 0)
PY
  ;;
cleanup)
  d=$(cat "$STATE/stamp" 2>/dev/null || true)
  if [ -n "$d" ]; then
    rm -rf "$HOME/TidyKeep-$d" "$HOME/Library/Caches/TidyKeep-$d-B"
    # Anything a failed run left behind.
    while IFS= read -r p; do rm -rf "$p"; done < "$STATE/canaries"
  fi
  rm -rf "$STATE"
  echo "User canaries cleaned up."
  ;;
*) echo "usage: $0 setup|check|cleanup" >&2; exit 2 ;;
esac
