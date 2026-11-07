#!/bin/bash
# Verify the real runs since the seed in the `tidytest` account (spec 017 §5): every item the run logs
# say were done is gone (delete) or in the Trash (trash), and every other path from the
# snapshot is still there (tripwires byte for byte). Prints PASS/FAIL per item.
set -euo pipefail
if [ "$(id -un)" != "tidytest" ]; then
  echo "Refusing: run this as the 'tidytest' user (you are $(id -un))." >&2
  exit 1
fi
exec /usr/bin/env python3 -I - "$HOME" <<'PY'
import hashlib, json, os, pathlib, stat, sys
home = pathlib.Path(sys.argv[1])
snap = home / ".tidytest-snapshot.tsv"
logs = sorted((home / "Library/Application Support/TidyMyMac/RunLog").glob("*.jsonl"))
# Every real run since the seed (Tidy Up, Uninstaller, Trash bins), oldest first.
since = snap.stat().st_mtime
runs = []
for f in logs:
    if f.stat().st_mtime < since: continue
    lines = [json.loads(l) for l in f.read_text().splitlines() if l.strip().startswith("{") and l.strip().endswith("}")]
    if lines and lines[0].get("type") == "header" and not lines[0].get("dryRun"):
        runs.append((f, lines))
if not runs:
    sys.exit("No real run since the seed found in the run log.")
fails = 0
def report(ok, msg):
    global fails
    fails += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + msg)

done = []
for f, lines in runs:
    items = [l for l in lines if l.get("type") == "item"]
    ok = [i for i in items if i["result"] == "done"]
    print(f"Run {f.name} ({lines[0].get('module')}): {len(ok)} done, {len(items) - len(ok)} skipped or failed")
    if lines[-1].get("type") != "summary":
        report(False, f"{f.name} has no summary line (interrupted)")
    done += ok
deleted = [i["path"] for i in done if i["action"] == "delete"]
def gone_later(t): return any(t == d or t.startswith(d + "/") for d in deleted)
# ~/.Trash is privacy-protected: without Full Disk Access for the terminal it reads as empty.
try:
    os.listdir(home / ".Trash"); trash_readable = True
except PermissionError:
    trash_readable = False
    print("NOTE can't read ~/.Trash: give your terminal app Full Disk Access in this account to check trashed items")
unchecked = 0
for i in done:
    p = i["path"]
    if i["action"] == "delete":
        report(not os.path.lexists(p), f"deleted {p}")
    elif i["action"] == "trash":
        t = i.get("trashPath") or ""
        # A later Trash-bins run may have emptied it.
        if not trash_readable and not gone_later(t):
            unchecked += 1
            report(not os.path.lexists(p) and ".Trash" in t, f"moved out (Trash not readable) {p} -> {t}")
            continue
        report(not os.path.lexists(p) and ".Trash" in t and (os.path.lexists(t) or gone_later(t)), f"trashed {p} -> {t}")

removed = [i["path"] for i in done]
def under(p): return any(p == r or p.startswith(r + "/") for r in removed)
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()
checked = 0
for line in snap.read_text().splitlines():
    p, inode, tripwire, extra = line.split("\t")
    if under(p): continue
    checked += 1
    if not os.path.lexists(p):
        report(False, f"missing (not selected): {p}"); continue
    st = os.lstat(p)
    if str(st.st_ino) != inode:
        # macOS rewrites some of its own files atomically (new inode), e.g. the services cache.
        if tripwire == "yes": report(False, f"tripwire replaced: {p}")
        else: print(f"WARN replaced (not seeded by us, may be the system): {p}")
        continue
    if extra.startswith("link:"):
        if os.readlink(p) != extra[5:]: report(False, f"link changed: {p}")
    elif extra != "dir" and stat.S_ISREG(st.st_mode) and sha(p) != extra:
        if tripwire == "yes": report(False, f"tripwire changed: {p}")
        else: print(f"WARN content changed (not seeded by us, may be the system): {p}")
print(f"Checked {checked} untouched paths.")
if fails: print(f"RESULT: FAIL ({fails})")
elif unchecked: print(f"RESULT: PASS, but {unchecked} trashed items weren't confirmed in the Trash (see NOTE)")
else: print("RESULT: PASS")
sys.exit(1 if fails else 0)
PY
