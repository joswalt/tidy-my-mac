#!/bin/bash
# Verify the last real run in the `tidytest` account (spec 017 §5): every item the run log
# says was done is gone (delete) or in the Trash (trash), and every other path from the
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
runs = []
for f in logs:
    lines = [json.loads(l) for l in f.read_text().splitlines() if l.strip().startswith("{") and l.strip().endswith("}")]
    if lines and lines[0].get("type") == "header" and not lines[0].get("dryRun"):
        runs.append((f, lines))
if not runs:
    sys.exit("No real run found in the run log.")
f, lines = runs[-1]
items = [l for l in lines if l.get("type") == "item"]
done = [i for i in items if i["result"] == "done"]
fails = 0
def report(ok, msg):
    global fails
    fails += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + msg)

print(f"Run {f.name}: {len(done)} done, {len(items) - len(done)} skipped or failed")
if lines[-1].get("type") != "summary":
    report(False, "run has no summary line (interrupted)")
for i in done:
    p = i["path"]
    if i["action"] == "delete":
        report(not os.path.lexists(p), f"deleted {p}")
    elif i["action"] == "trash":
        t = i.get("trashPath") or ""
        report(not os.path.lexists(p) and os.path.lexists(t) and ".Trash" in t, f"trashed {p} -> {t}")

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
        report(False, f"replaced: {p}"); continue
    if extra.startswith("link:"):
        if os.readlink(p) != extra[5:]: report(False, f"link changed: {p}")
    elif extra != "dir" and stat.S_ISREG(st.st_mode) and sha(p) != extra:
        if tripwire == "yes": report(False, f"tripwire changed: {p}")
        else: print(f"WARN content changed (not seeded by us, may be the system): {p}")
print(f"Checked {checked} untouched paths.")
print("RESULT: PASS" if fails == 0 else f"RESULT: FAIL ({fails})")
sys.exit(1 if fails else 0)
PY
