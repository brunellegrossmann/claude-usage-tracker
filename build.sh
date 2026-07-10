#!/bin/bash
# Build the SwiftPM release binary and wrap it in a self-contained .app bundle.
# Usage: ./build.sh [output-app-path]
#   Default output: ~/Applications/Claude Code Usage.app
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-$HOME/Applications/Claude Code Usage.app}"
EXEC_NAME="ClaudeCodeUsage"

echo "Building (release) -> $APP"
swift build --package-path "$REPO_DIR" -c release
BIN="$(swift build --package-path "$REPO_DIR" -c release --show-bin-path)/${EXEC_NAME}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REPO_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/${EXEC_NAME}"

# Stamp the version the running app reports (the in-app update check compares it
# against the latest GitHub release tag). Prefer $APP_VERSION (set by the release
# workflow from the git tag), else the current git tag, else the Info.plist default.
VERSION="${APP_VERSION:-$(git -C "$REPO_DIR" describe --tags 2>/dev/null || true)}"
VERSION="${VERSION#v}"
if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    echo "Stamped version $VERSION"
fi

# Ad-hoc codesign so SMAppService (launch-at-login) accepts a stable identity.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
