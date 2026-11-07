#!/bin/bash
# Rule lint (spec 006 §6 step 1). Checks every Rules/*.json file. Runs in CI and locally.
# Milestone 0 covers the structural checks; milestone 1 adds JSON Schema validation,
# protected-floor overlap and helper-zone checks via RuleEngine's own linter.
set -euo pipefail
cd "$(dirname "$0")/.."
exec /usr/bin/env python3 -I - Rules <<'PY'
import json, pathlib, sys

rules_dir = pathlib.Path(sys.argv[1])
errors = []
ALLOWED_LICENCES = {"own", "MIT", "Apache-2.0"}
DELETE_OK_CATEGORIES = {"cache", "log"}
seen_ids = {}

files = sorted(rules_dir.glob("*.json"))
for path in files:
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        errors.append(f"{path}: not valid JSON ({e})")
        continue
    if path.name == "schema.json":
        continue
    if doc.get("schemaVersion") != 1:
        errors.append(f"{path}: schemaVersion must be 1")
    rules = doc.get("rules")
    if not isinstance(rules, list):
        errors.append(f"{path}: 'rules' must be a list")
        continue
    for i, r in enumerate(rules):
        where = f"{path}#{i}"
        rid = r.get("id") or r.get("bundleId")
        if rid is None:
            errors.append(f"{where}: missing id"); continue
        where = f"{path}:{rid}"
        if rid in seen_ids:
            errors.append(f"{where}: duplicate id (also in {seen_ids[rid]})")
        seen_ids[rid] = path.name
        src = r.get("source")
        if "source" in r or "category" in r:
            if not isinstance(src, dict) or src.get("license") not in ALLOWED_LICENCES:
                errors.append(f"{where}: source.license must be one of {sorted(ALLOWED_LICENCES)}")
        action, category, risk = r.get("action"), r.get("category"), r.get("risk")
        if action == "delete" and category not in DELETE_OK_CATEGORIES:
            errors.append(f"{where}: 'delete' is only allowed for caches and logs")
        if risk == "risky" and action == "delete":
            errors.append(f"{where}: risky rules never delete")
        if risk == "safe" and not r.get("evidence"):
            errors.append(f"{where}: safe rules need evidence")

for e in errors:
    print("lint-rules:", e)
if errors:
    print(f"lint-rules: FAILED ({len(errors)} problem(s))"); sys.exit(1)
print(f"lint-rules: OK ({len(files)} file(s), {len(seen_ids)} rule(s))")
PY
