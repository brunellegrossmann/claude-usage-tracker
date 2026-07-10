#!/bin/bash
# Quit the app and remove the installed bundle.
set -euo pipefail

APP="$HOME/Applications/Claude Code Usage.app"

echo "Tip: before uninstalling, open the menu and turn OFF 'Launch at login'"
echo "so macOS drops the login-item registration cleanly."
echo

pkill -x ClaudeCodeUsage 2>/dev/null || true
sleep 1
rm -rf "$APP"
echo "Removed $APP"
echo "If it still shows under System Settings ▸ General ▸ Login Items, remove it there."
