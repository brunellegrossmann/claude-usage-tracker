#!/bin/bash
# Emit the Homebrew cask for one release to stdout.
#
# Usage: bash Scripts/homebrew_cask.sh <version-without-v> <sha256>
#
# The cask lives in a separate tap repo (Homebrew only taps repos named
# homebrew-*), so the release workflow attaches this file to the release and
# updating the tap is a copy of one file. See RELEASING.md.
set -euo pipefail

VERSION="${1:?version required, without the leading v}"
SHA256="${2:?sha256 required}"

cat <<CASK
cask "claude-code-usage" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/brunellegrossmann/claude-usage-tracker/releases/download/v#{version}/Claude-Code-Usage-v#{version}.zip"
  name "Claude Code Usage"
  desc "Menu bar app showing what your Claude Code usage costs"
  homepage "https://github.com/brunellegrossmann/claude-usage-tracker"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Claude Code Usage.app"

  caveats <<~EOS
    This app is not signed with an Apple Developer ID and is not notarized, so
    macOS quarantines it and will refuse the first launch. Either install with

      brew install --cask --no-quarantine claude-code-usage

    or clear the flag afterwards:

      xattr -cr "/Applications/Claude Code Usage.app"

    That removes a macOS protection. You can verify the download came from the
    project's public CI first:

      gh attestation verify <downloaded zip> -R brunellegrossmann/claude-usage-tracker
  EOS

  zap trash: [
    "~/Library/Application Support/com.local.claudecodeusage",
    "~/Library/Preferences/com.local.claudecodeusage.plist",
  ]
end
CASK
