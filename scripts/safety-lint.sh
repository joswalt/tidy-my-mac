#!/bin/bash
# Safety lint (spec 017 §2). Fails if code reaches the real home folder, writes literal
# user/system paths, or removes files outside the few files allowed to. Runs in CI and locally.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { echo "safety-lint: $1"; fail=1; }

# Swift files the checks cover.
swift_files() { find App Helper Packages/TidyCore/Sources Packages/TidyCore/Tests -name '*.swift' 2>/dev/null | sort; }

# Allowed files per check (extended regexes on the repo-relative path).
# Composition root: the only app file that may build real file-system values (Home).
COMPOSITION_ROOT='^App/(TidyMyMacApp|CompositionRoot)\.swift$'
# Files that may hold literal system paths: the floor, helper zones, and their tests.
LITERAL_PATHS_OK='^Packages/TidyCore/(Sources|Tests)/(SafetyFloor|HelperCore)(Tests)?/'
# Files that may remove or trash: the floor, the RuleEngine remover, HelperCore, the composition root.
REMOVERS_OK='^Packages/TidyCore/Sources/(SafetyFloor/|HelperCore/|RuleEngine/Remover[^/]*\.swift$)|^App/(TidyMyMacApp|CompositionRoot)\.swift$'
# TestHome builds fixture homes in the temp dir.
TESTHOME_OK='/TestHome[^/]*\.swift$'

check() { # name, regex, allowed-path-regex
  local name="$1" pattern="$2" allowed="$3" f
  while IFS= read -r f; do
    [[ "$f" =~ $allowed ]] && continue
    [[ "$f" =~ $TESTHOME_OK ]] && continue
    if grep -nE "$pattern" "$f" >/dev/null; then
      grep -nE "$pattern" "$f" | sed "s|^|$f:|" | while IFS= read -r hit; do echo "  $hit"; done
      report "$name in $f"
    fi
  done < <(swift_files)
}

# 1. Real home folder APIs, only in the composition root.
check "home-folder API" 'NSHomeDirectory\(|homeDirectoryForCurrentUser|homeDirectory\(forUser|\.urls\(for:|NSSearchPathForDirectoriesInDomains' "$COMPOSITION_ROOT"
# 2. Literal user or system paths.
check "literal path" '"(/Users/|~/|/Library/)' "$LITERAL_PATHS_OK"
# 3. Removal APIs.
check "removal API" 'removeItem\(|trashItem\(|[^A-Za-z_]unlink\(|[^A-Za-z_]rmdir\(|unlinkat\(' "$REMOVERS_OK"
# 4. Libraries never import SwiftUI (spec 016 §3).
while IFS= read -r f; do
  grep -nE '^\s*import\s+SwiftUI' "$f" >/dev/null && report "SwiftUI imported in library file $f"
done < <(find Packages/TidyCore/Sources -name '*.swift' | sort)
# 5. UI never touches the file system (spec 016 §3): no FileManager in App/ outside the composition root.
while IFS= read -r f; do
  [[ "$f" =~ $COMPOSITION_ROOT ]] && continue
  grep -nE 'FileManager' "$f" >/dev/null && report "FileManager used in UI file $f"
done < <(find App -name '*.swift' | sort)

# 6. Required test cases must exist (spec 017 D6). Each milestone adds its named files here.
REQUIRED_TEST_FILES=(
  # milestone 1: Packages/TidyCore/Tests/EndToEndTests/SnapshotDiffTests.swift, ...
)
for t in ${REQUIRED_TEST_FILES[@]+"${REQUIRED_TEST_FILES[@]}"}; do
  [ -f "$t" ] || report "required test file missing: $t"
done

if [ "$fail" -ne 0 ]; then echo "safety-lint: FAILED"; exit 1; fi
echo "safety-lint: OK"
