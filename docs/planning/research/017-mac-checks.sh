#!/bin/bash
# Ticket 017: the shell-only one-minute checks (research 015 Q2, research 013 timing).
# Run in Apple Terminal on John's Mac: bash 017-mac-checks.sh | tee 017-results.txt
# Reads only; opens System Settings panes; never installs or downloads anything.
set -u
echo "== macOS"; sw_vers
echo; echo "== softwareupdate -l, run 1"; time softwareupdate -l 2>&1
echo; echo "== softwareupdate -l, run 2"; time softwareupdate -l 2>&1
echo; echo "== softwareupdate -l --no-scan"; time softwareupdate -l --no-scan 2>&1
echo; echo "== SoftwareUpdate plist readable without root?"
defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable 2>&1
defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist RecommendedUpdates 2>&1 | head -20
for url in \
  "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" \
  "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles" \
  "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"; do
  echo; echo "== deep link: $url"
  open "$url"; echo "open exit: $?"
  read -r -p "What did System Settings show? (type a few words, Enter) " seen
  echo "seen: $seen"
done
