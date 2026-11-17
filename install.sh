#!/bin/bash
# Builds Search and puts it in /Applications, in place of the copy there.
# The fork has no updater: this is how it is updated, after a pull or a
# rebase onto upstream.
#
#   ./install.sh                    build, then install into /Applications
#   ./install.sh ~/Applications     the same, for this account only
#
# A Search already running from there is quit first, and opened again once
# the new copy is in.
set -euo pipefail

cd "$(dirname "$0")"
DIR="${1:-/Applications}"
TARGET="$DIR/Search.app"
BINARY="$TARGET/Contents/MacOS/Search"

[ -d "$DIR" ] || { echo "no folder $DIR" >&2; exit 1; }

./build.sh release

# Quit the installed copy, as ⌘Q would, so its session is saved; another
# copy (a dev build, build/Search.app) is left running.
WAS_RUNNING=""
if pgrep -qf "^$BINARY" ; then
  WAS_RUNNING=1
  osascript -e "tell application \"$TARGET\" to quit" >/dev/null
  for _ in $(seq 1 100); do
    pgrep -qf "^$BINARY" || break
    sleep 0.1
  done
  if pgrep -qf "^$BINARY"; then
    echo "Search in $DIR didn't quit — quit it and run this again" >&2
    exit 1
  fi
fi

# The new copy goes in beside the old one first, so a failed copy leaves
# the old one where it was.
NEW="$DIR/.Search.app.new"
rm -rf "$NEW"
ditto build/Search.app "$NEW"
rm -rf "$TARGET"
mv "$NEW" "$TARGET"
echo "installed: $TARGET ($(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?"))"

[ -n "$WAS_RUNNING" ] && open "$TARGET"
exit 0
