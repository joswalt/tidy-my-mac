#!/bin/bash
# Local checks that need John's Mac (spec 017 §3, §6 short form step 2):
# all tests and lints, a signed build, codesign verification and the helper plist.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { echo; echo "== $1"; }

step "Signing setup (spike 009)"
wwdr=$(security find-certificate -c "Apple Worldwide Developer Relations Certification Authority" -a -Z 2>/dev/null || true)
grep -q "SHA-1" <<<"$wwdr" || echo "warning: WWDR intermediate not found; import AppleWWDRCAG3.cer from https://www.apple.com/certificateauthority/"
ids=$(security find-identity -v -p codesigning)
grep -q "Apple Development" <<<"$ids" \
  || { echo "No 'Apple Development' signing identity found."; exit 1; }

step "Package tests"
swift test --package-path Packages/TidyCore

step "Lints"
scripts/lint-rules.sh
scripts/safety-lint.sh
scripts/test-scripts.sh

step "Signed build"
xcodegen generate
xcodebuild -project TidyMyMac.xcodeproj -scheme TidyMyMac -configuration Release \
  -derivedDataPath build/DerivedData build -quiet
APP=build/DerivedData/Build/Products/Release/TidyMyMac.app

step "Code signature"
codesign --verify --deep --strict "$APP"
for bin in "$APP" "$APP/Contents/MacOS/TidyMyMacHelper"; do
  info=$(codesign -dvv "$bin" 2>&1)
  grep -q "TeamIdentifier=26TUUFN7M2" <<<"$info" || { echo "$bin: wrong team"; exit 1; }
  grep -q "(runtime)" <<<"$info" || { echo "$bin: hardened runtime off"; exit 1; }
  grep -q "Signature=adhoc" <<<"$info" && { echo "$bin: ad hoc signed"; exit 1; }
  # A debuggable build lets any process running as you attach to it (security review, finding 6).
  gta=$(codesign -d --entitlements - --xml "$bin" 2>/dev/null \
        | plutil -extract com.apple.security.get-task-allow raw -o - - 2>/dev/null || true)
  [ "$gta" = true ] && { echo "$bin: get-task-allow is on (debuggable); a Release build must not have it"; exit 1; }
  grep -E '^Identifier=' <<<"$info"
done
helper_info=$(codesign -dvv "$APP/Contents/MacOS/TidyMyMacHelper" 2>&1)
grep -qx "Identifier=io.github.joswalt.TidyMyMac.Helper" <<<"$helper_info" \
  || { echo "helper signing identifier is wrong"; exit 1; }

step "Helper launchd plist"
PLIST="$APP/Contents/Library/LaunchDaemons/io.github.joswalt.TidyMyMac.Helper.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST")" = "io.github.joswalt.TidyMyMac.Helper" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$PLIST")" = "Contents/MacOS/TidyMyMacHelper" ]
[ -x "$APP/Contents/MacOS/TidyMyMacHelper" ]

echo; echo "check-local: OK ($APP)"
