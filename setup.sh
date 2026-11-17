#!/bin/bash
# Saves your claude.ai sessionKey cookie into the macOS Keychain.
set -e

echo "Paste your claude.ai sessionKey (starts with sk-ant-sid01-)."
echo "Find it in browser DevTools → Application → Cookies → claude.ai."
printf "sessionKey (input hidden): "
read -rs KEY
echo

KEY=$(printf '%s' "$KEY" | tr -d '[:space:]"')
case "$KEY" in
  sk-ant-sid*) ;;
  *) echo "That doesn't look like a sessionKey (expected prefix sk-ant-sid0N-). Nothing saved." >&2; exit 1 ;;
esac

security add-generic-password -s claude-usage -a sessionKey -w "$KEY" -U
rm -f "$HOME/Library/Caches/claude-usage/org_id"
echo "Saved to Keychain (service: claude-usage). Refresh the SwiftBar plugin to see usage."
