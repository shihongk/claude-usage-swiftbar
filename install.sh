#!/bin/bash
# Installs the Claude usage plugin into your SwiftBar plugins folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="claude-usage.5m.sh"

if [ ! -d /Applications/SwiftBar.app ]; then
  echo "SwiftBar is not installed. Install it first:  brew install --cask swiftbar"
  echo "Then launch it once and choose a plugins folder."
  exit 1
fi

DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$DIR" ]; then
  echo "SwiftBar has no plugins folder yet. Launch SwiftBar, choose a folder, then rerun this script."
  echo "(Or pass one yourself:  ./install.sh /path/to/plugins)"
  [ -z "$1" ] && exit 1
fi
[ -n "$1" ] && DIR="$1"

mkdir -p "$DIR"
cp "$HERE/$PLUGIN" "$DIR/$PLUGIN"
chmod +x "$DIR/$PLUGIN"
echo "Installed to $DIR/$PLUGIN"

if ! security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
  echo
  echo "No Claude Code login found. Either run 'claude' and use /login with your Claude subscription,"
  echo "or run ./setup.sh to use a claude.ai sessionKey cookie instead (may be blocked by Cloudflare)."
fi
echo "In SwiftBar: menu → Refresh All."
