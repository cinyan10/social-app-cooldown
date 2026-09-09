#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_PATH="${ROOT}/.build/SocialCooldown.app"

# The app intentionally ignores ⌘Q and the normal menu quit action. A targeted
# TERM signal is used here so development restarts can still stop the old build.
/usr/bin/pkill -TERM -x SocialCooldown 2>/dev/null || true

# Give the old process a moment to exit before replacing its executable.
for _ in {1..30}; do
    if ! /usr/bin/pgrep -x SocialCooldown >/dev/null 2>&1; then
        break
    fi
    /bin/sleep 0.1
done

# If it did not exit cleanly, force-stop only the exact app process.
if /usr/bin/pgrep -x SocialCooldown >/dev/null 2>&1; then
    /usr/bin/pkill -KILL -x SocialCooldown 2>/dev/null || true
fi

"${ROOT}/scripts/build-app.sh"
/usr/bin/open "$APP_PATH"
