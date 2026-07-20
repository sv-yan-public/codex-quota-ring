#!/bin/zsh
set -euo pipefail

launchctl bootout "gui/$UID/dev.quota-ring.codex" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/dev.quota-ring.codex.plist"
rm -rf "$HOME/Applications/Codex Quota Ring.app"
echo "Codex Quota Ring has been removed."
