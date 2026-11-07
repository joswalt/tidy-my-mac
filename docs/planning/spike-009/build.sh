#!/bin/bash
# Usage: ./build.sh "<signing identity>"   e.g. "Apple Development: john@example.com (ABCDE12345)"
#        ./build.sh -                      (ad-hoc, for comparison only)
set -euo pipefail
ID="${1:?pass signing identity or - for ad hoc}"
cd "$(dirname "$0")"
OUT=build/TidySpike.app
rm -rf build && mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Library/LaunchDaemons"
if [ "$ID" = "-" ]; then TEAM="ADHOC"; else
  TEAM=$(security find-certificate -c "$ID" -p | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/{print $2}')
fi
echo "Team (OU): $TEAM"
if [ "$ID" != "-" ]; then security find-certificate -c "$ID" -p | openssl x509 -noout -dates; fi  # spec 005 Q6: cert lifetime
echo "let spikeTeamID = \"$TEAM\"" > build/TeamID.swift
sed "s/BUILDNUM/$(date +%s)/" Info.plist > "$OUT/Contents/Info.plist"
cp com.tidymymac.spike.helper.plist "$OUT/Contents/Library/LaunchDaemons/"
mkdir -p build/h build/a; cp Helper.swift build/h/main.swift; cp App.swift build/a/main.swift  # top-level code must live in main.swift
swiftc -O -target arm64-apple-macos14 Shared.swift build/TeamID.swift build/h/main.swift -o "$OUT/Contents/MacOS/TidySpikeHelper"
swiftc -O -target arm64-apple-macos14 Shared.swift build/a/main.swift -o "$OUT/Contents/MacOS/TidySpike"
codesign --force --options runtime --timestamp=none -i com.tidymymac.spike.helper -s "$ID" "$OUT/Contents/MacOS/TidySpikeHelper"
codesign --force --options runtime --timestamp=none -s "$ID" "$OUT"
codesign -dvv "$OUT" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier' || true
echo "Built $OUT"
