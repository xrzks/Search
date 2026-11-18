#!/bin/bash
# Builds Search and puts it in /Applications, in place of the copy there.
# The fork has no updater: this is how it is updated, after a pull or a
# rebase onto upstream.
#
#   ./install.sh                    build, then install into /Applications
#   ./install.sh ~/Applications     the same, for this account only
#   ./install.sh --test             run the unit tests first (swift test);
#                                   a failure installs nothing
#   ./install.sh --dirty            install with changes not yet committed
#
# What is installed is a commit: with changes in the working tree (anything
# but Markdown), nothing is built unless --dirty says so, so the copy in
# /Applications can always be named. The commit and the signature it got
# are said at the end.
#
# A Search already running from there is quit first, and opened again once
# the new copy is in.
set -euo pipefail

cd "$(dirname "$0")"
TEST="" DIRTY="" DIR=""
for arg in "$@"; do
  case "$arg" in
    --test) TEST=1 ;;
    --dirty) DIRTY=1 ;;
    -*) echo "usage: ./install.sh [--test] [--dirty] [FOLDER]" >&2; exit 1 ;;
    *) [ -z "$DIR" ] || { echo "one folder at most" >&2; exit 1; }; DIR="$arg" ;;
  esac
done
DIR="${DIR:-/Applications}"
TARGET="$DIR/Search.app"
BINARY="$TARGET/Contents/MacOS/Search"

[ -d "$DIR" ] || { echo "no folder $DIR" >&2; exit 1; }

# Changes that would go into the build, untracked files included: SwiftPM
# compiles every file in Sources/, committed or not.
CHANGES="$(git status --porcelain -- . ':!*.md')"
if [ -n "$CHANGES" ] && [ -z "$DIRTY" ]; then
  echo "not committed — commit first, or --dirty to install them anyway:" >&2
  echo "$CHANGES" >&2
  exit 1
fi
COMMIT="$(git rev-parse --short HEAD)"
[ -n "$CHANGES" ] && COMMIT="$COMMIT + changes"

if [ -n "$TEST" ]; then
  swift test || { echo "tests failed: nothing installed" >&2; exit 1; }
fi

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

# How build.sh signed it: a Developer ID when the keychain has one (the
# first found, unless SEARCH_SIGN_IDENTITY names one), ad-hoc otherwise.
SIGNED="$(codesign -dv "$TARGET" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
VERSION="$(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
echo "installed: $TARGET ($VERSION, $COMMIT)"
echo "signed:    ${SIGNED:-ad-hoc}"

[ -n "$WAS_RUNNING" ] && open "$TARGET"
exit 0
