#!/bin/bash
# A temporary `tidytest` account for releases that change SafetyFloor, HelperCore or Helper/
# (spec 017 §5). Made for the run and deleted afterwards, so no test account stays on the Mac.
#   sudo scripts/tidytest-account.sh create   standard (not admin) user `tidytest` with a random
#                                             password (printed), and the seed/verify scripts in
#                                             /Users/Shared/TidyTest
#   sudo scripts/tidytest-account.sh delete   deletes the account, its home folder and the scripts
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
USER_NAME=tidytest
SHARED=/Users/Shared/TidyTest
cd "$(dirname "$0")/.."

case "${1:-}" in
create)
  if id "$USER_NAME" >/dev/null 2>&1; then echo "$USER_NAME already exists." >&2; exit 1; fi
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
  sysadminctl -addUser "$USER_NAME" -fullName "TidyMyMac Test" -password "$pw" -home "/Users/$USER_NAME" 2>&1 | grep -v '^$' || true
  id "$USER_NAME" >/dev/null 2>&1 || { echo "Couldn't create $USER_NAME." >&2; exit 1; }
  createhomedir -c -u "$USER_NAME" >/dev/null
  # /Users/Shared is world-writable (1777): a folder or symlink planted there first would get
  # root's copies and chmod. Only reuse our own root-owned folder; refuse anything else.
  if [ -L "$SHARED" ] || { [ -e "$SHARED" ] && { [ ! -d "$SHARED" ] || [ "$(stat -f %u "$SHARED")" != 0 ]; }; }; then
    echo "Refusing: $SHARED exists and isn't a folder owned by root. Remove it, then try again." >&2
    exit 1
  fi
  rm -rf "$SHARED"
  mkdir -m 755 "$SHARED"
  install -m 755 scripts/seed-tidytest.sh scripts/verify-tidytest.sh "$SHARED/"
  echo
  echo "Created standard user '$USER_NAME'. Password: $pw"
  echo "Log in as $USER_NAME (Fast User Switching), skip the setup screens, then in Terminal:"
  echo "  $SHARED/seed-tidytest.sh"
  echo "Then open /Applications/TidyMyMac.app, grant Full Disk Access when asked, run Tidy Up with defaults,"
  echo "Applications › Uninstaller on 'TidyTest Dummy', then empty the Trash bins in Cleanup, then:"
  echo "  $SHARED/verify-tidytest.sh"
  ;;
delete)
  if id "$USER_NAME" >/dev/null 2>&1; then
    # Log the account out first if it is still signed in.
    uid=$(id -u "$USER_NAME")
    launchctl bootout "user/$uid" 2>/dev/null || true
    sysadminctl -deleteUser "$USER_NAME" 2>&1 | grep -v '^$' || true
    id "$USER_NAME" >/dev/null 2>&1 && { echo "Couldn't delete $USER_NAME." >&2; exit 1; }
  fi
  rm -rf "$SHARED" "/Users/$USER_NAME"
  echo "Deleted '$USER_NAME' and its home folder."
  ;;
*) echo "usage: sudo $0 create|delete" >&2; exit 2 ;;
esac
