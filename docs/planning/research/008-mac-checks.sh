#!/bin/zsh
# TidyMyMac ticket 008: three permission checks on a real Mac.
# Usage:  zsh 008-mac-checks.sh /Applications/SomeSpareApp.app
#
# Before running:
#  - Pick a spare app you can reinstall: downloaded from the web (NOT App Store,
#    NOT made by Apple), installed by dragging to /Applications, opened at least once.
#  - System Settings > Privacy & Security > App Management: Terminal must be OFF or absent.
#  - System Settings > Privacy & Security > Full Disk Access: turn Terminal OFF for this
#    test (quit and reopen Terminal after). You can turn it back on afterwards.
#
# What it changes: creates and deletes one empty test file inside the spare app,
# renames the app and renames it back, resets the spare app's privacy permissions,
# and (only if you type y) moves the spare app to the Trash.

APP="${1%/}"
if [[ ! -d "$APP" || "$APP" != *.app ]]; then echo "Give the path to a spare .app"; exit 1; fi
BID=$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)
r() { echo "\$ $*"; "$@" 2>&1 | head -5; echo "  -> exit=${pipestatus[1]}"; }

echo "== Setup"
echo "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m), user $(id -un)"
echo "App: $APP  bundle id: $BID  owner: $(stat -f %Su "$APP")"
codesign -dv "$APP" 2>&1 | grep -E "TeamIdentifier|Authority=Developer ID" | head -2
xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1 && echo "quarantine xattr: present" || echo "quarantine xattr: none"
if ls "$HOME/Library/Application Support/com.apple.TCC" >/dev/null 2>&1; then
  echo "Terminal Full Disk Access: YES (turn it off for a clean Q3 result)"
else
  echo "Terminal Full Disk Access: no"
fi

echo; echo "== Q3: reading ~/.Trash without Full Disk Access"
r ls -ld "$HOME/.Trash"
r ls -A "$HOME/.Trash"
r du -sk "$HOME/.Trash"
TF="$HOME/.Trash/tidytest-$$.txt"
r touch "$TF"
rm -f "$TF" 2>/dev/null

echo; echo "== Q2: tccutil reset without root (spare app: $BID)"
for svc in Camera Microphone ScreenCapture Accessibility SystemPolicyAllFiles All; do
  r tccutil reset $svc "$BID"
done

echo; echo "== Q1: App Management (Terminal has no App Management permission)"
r touch "$APP/Contents/tidytest"
rm -f "$APP/Contents/tidytest" 2>/dev/null
REN="${APP%.app}-tidytest.app"
r mv "$APP" "$REN"
[[ -d "$REN" ]] && { mv "$REN" "$APP" && echo "  (renamed back)"; }
echo
read "ans?Move the spare app to the Trash to test deleting it? Type y to do it: "
if [[ "$ans" == y ]]; then
  r mv "$APP" "$HOME/.Trash/"
  r osascript -e "tell application \"Finder\" to delete (POSIX file \"$APP\" as alias)"
  [[ -d "$APP" ]] && echo "  App is STILL in place" || echo "  App is GONE from its folder (use Finder > Trash > Put Back to restore)"
fi
echo; echo "Done. Also note any 'Terminal was prevented from modifying apps' notification or permission prompt you saw."
