#!/bin/bash
# Seed the throwaway `tidytest` account for a real run (spec 017 §5).
# Run as tidytest only: it writes junk and tripwire files into the CURRENT home folder,
# then records a snapshot that verify-tidytest.sh compares against after the run.
set -euo pipefail
if [ "$(id -un)" != "tidytest" ]; then
  echo "Refusing: run this as the 'tidytest' user (you are $(id -un))." >&2
  exit 1
fi
cd "$HOME"
SNAP="$HOME/.tidytest-snapshot.tsv"

mkfile() { mkdir -p "$(dirname "$1")"; head -c "${2:-4096}" /dev/urandom > "$1"; }

# Junk for every user-level rule.
mkfile "Library/Caches/com.example.Editor/Cache.db" 40960
mkfile "Library/Caches/com.example.Big/blob" 3000000
mkfile "Library/Logs/DiagnosticReports/Example.crash"
mkfile "Library/Logs/com.example.log"
mkfile "Library/Developer/Xcode/DerivedData/App-abc/Build/x" 81920
mkfile "Library/Developer/Xcode/UserData/Previews/Simulator Devices/x"
mkfile "Library/Developer/Xcode/iOS DeviceSupport/iPhone 18.0/Symbols/x"
mkfile "Library/Developer/Xcode/Archives/2026-11-07/App.xcarchive/Info.plist"
mkfile ".ollama/models/blobs/sha256-1" 40960
mkfile ".lmstudio/models/org/model.gguf" 40960
mkfile ".cache/huggingface/hub/models--org--name/blobs/x" 40960
mkfile "Downloads/Tool-1.2.dmg" 40960
mkdir -p Library/LaunchAgents
/usr/libexec/PlistBuddy -c "Add :Label string com.example.gone" -c "Add :Program string $HOME/Applications/Gone.app/Contents/MacOS/Gone" \
  "Library/LaunchAgents/com.example.gone.plist" >/dev/null

# Tripwires that must survive byte for byte.
TRIPWIRES=()
for f in Documents/tw.txt Desktop/tw.txt Pictures/tw.jpg Movies/tw.mov Music/tw.m4a \
         "Library/Mobile Documents/com~apple~CloudDocs/tw.txt" "Library/Application Support/TidyMyMac/tw.json" \
         "Library/Logs/TidyMyMac/tw.log" "Library/Caches/com.apple.something/tw" \
         "Applications/Foo.app/Contents/Info.plist" Downloads/report.pdf Documents/linked.bin Documents/cloned.bin; do
  mkfile "$f" 8192
  TRIPWIRES+=("$HOME/$f")
done
ln -sf "$HOME/Documents" "Library/Caches/escape"
ln -sf "$HOME/Documents" "Library/Caches/com.example.Editor/docs-link"
mkdir -p Library/Caches/com.example.Links Library/Caches/com.example.Clones Library/Caches/com.example.Locked
ln -f Documents/linked.bin Library/Caches/com.example.Links/hard.bin
cp -c Documents/cloned.bin Library/Caches/com.example.Clones/clone.bin
mkfile Library/Caches/com.example.Locked/locked
chflags uchg Library/Caches/com.example.Locked/locked

# Snapshot of the seeded areas: path, inode, tripwire flag, sha256 (files) or link target.
# Other parts of the home churn on their own (preferences, system caches) and are not compared.
is_tripwire() { local t; for t in "${TRIPWIRES[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
: > "$SNAP"
AREAS=(Library/Caches Library/Logs Library/Developer Library/LaunchAgents "Library/Mobile Documents" \
       "Library/Application Support/TidyMyMac" .ollama .lmstudio .cache/huggingface Applications \
       Downloads Documents Desktop Pictures Movies Music)
for a in "${AREAS[@]}"; do
  find "$HOME/$a" -path "$HOME/Library/Application Support/TidyMyMac/RunLog" -prune -o -print 2>/dev/null
done | while IFS= read -r p; do
  inode=$(stat -f %i "$p" 2>/dev/null) || continue
  if [ -L "$p" ]; then extra="link:$(readlink "$p")"
  elif [ -f "$p" ]; then extra=$(shasum -a 256 "$p" 2>/dev/null | cut -d' ' -f1)
  else extra="dir"; fi
  tw=no; is_tripwire "$p" && tw=yes
  printf '%s\t%s\t%s\t%s\n' "$p" "$inode" "$tw" "$extra" >> "$SNAP"
done
echo "Seeded. Snapshot: $SNAP ($(wc -l < "$SNAP") paths)."
echo "Now: open TidyMyMac from /Applications, run Cleanup or Smart Care with what you want ticked, then run scripts/verify-tidytest.sh."
