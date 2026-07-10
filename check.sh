#!/bin/bash
# Compile gate plus unit tests. Run before rebuilding the app; fails fast on any
# compile error or test failure, without producing the .app bundle.
#
# The app always compiles here (that is the gate). Unit tests need a test
# framework (XCTest), which ships with full Xcode but not with the Command Line
# Tools. When only the CLT are installed, tests are skipped locally and run in
# CI instead (GitHub's macOS runners have Xcode).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "-> Compiling app targets (the gate)..."
swift build --package-path "$REPO_DIR"

if xcrun --find xctest >/dev/null 2>&1; then
    echo "-> Compiling and running unit tests..."
    swift test --package-path "$REPO_DIR"
    echo "OK: everything compiles and tests pass."
else
    echo "note: XCTest unavailable (Command Line Tools only); skipping tests locally."
    echo "      Tests run in CI. To run them here, install Xcode and:"
    echo "      sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "OK: app compiles (tests skipped locally)."
fi
