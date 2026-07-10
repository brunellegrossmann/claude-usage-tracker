#!/bin/bash
# Build, install to ~/Applications, and launch. Re-run any time to update.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/Claude Code Usage.app"

if ! command -v swift >/dev/null 2>&1; then
    echo "error: swift not found. Install the Xcode Command Line Tools:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi

# Stop a running instance so the binary can be replaced.
pkill -x ClaudeCodeUsage 2>/dev/null || true
sleep 1

bash "$REPO_DIR/build.sh" "$APP"

open "$APP"
echo
echo "Installed and launched. Look for '\$today ▸ \$month' in your menu bar."
echo "It will launch automatically at every login (toggle in Settings)."
