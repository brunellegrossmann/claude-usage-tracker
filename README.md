# Claude Code Usage

A native macOS **menu-bar app** that shows what your Claude Code usage costs.
The menu bar shows **today's spend** behind a tier emoji at a glance.
The dropdown adds **month-to-date** (resetting on a configurable day, the 1st by
default), a projected month total, and a detailed breakdown.

```
🥇 $4.79
```

Unofficial. Not affiliated with, endorsed by, or supported by Anthropic.

It works no matter where you run Claude Code — direct terminal, Cursor, IDE
extension — because every session writes its token usage to
`~/.claude/projects/**/*.jsonl`, and that is the single source this app reads.

## Features

- **Menu bar:** tier emoji + today's spend (e.g. `🥇 $4.79`).
- **Month-to-date** in the dropdown.
- **Projected month total** — extrapolates your spend over the cycle's working
  days (set them in Settings; Mon–Fri by default).
- **Pace indicator** — today vs. your average spend across the days you were
  active (↑ above / ↓ below); days with no spend don't count.
- **Monthly budget bar** — spend vs. a configurable cap, on a configurable
  billing-cycle reset day (Settings ▸ General).
- **By-model breakdown** for the month (Opus / Sonnet / Haiku / Fable).
- **Today-by-hour and 14-day charts** — hover any bar for its hour/day and
  amount; the 14-day chart also shows a last-7-days total.
- **Tokens in / out today.**
- **Tier ladder** in the menu bar (e.g. medals up to 💎, then 💩 past budget) —
  pick a ladder and edit each step's name/threshold in Settings ▸ Tier Theme;
  the 🙂 button next to each step opens the native emoji picker.
- **Settings window** (Settings… in the popover footer): plan, launch at
  login, monthly budget, billing-cycle reset day, working days, tier ladder.
- **Launches at login** automatically (native login item; toggle in Settings).
- No dock icon (menu-bar only). No Python, no background daemon — one Swift binary.

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon or Intel.
- Nothing else to download the app.
- To build from source: Xcode Command Line Tools (`xcode-select --install`).
  Unit tests need full Xcode (XCTest isn't in the CLT); `check.sh` skips them
  locally without it and they still run in CI.

## Install

### Download the app

1. Grab `Claude-Code-Usage-vX.Y.Z.zip` from the
   [latest release](https://github.com/brunellegrossmann/claude-usage-tracker/releases/latest).
2. Unzip it and drag **Claude Code Usage.app** to `/Applications`.
3. First launch: **right-click the app ▸ Open**, then confirm. Or clear the
   quarantine flag from a terminal:

   ```sh
   xattr -cr "/Applications/Claude Code Usage.app"
   ```

macOS blocks that first launch because the app is not signed with an Apple
Developer ID - see [Is this safe to run?](#is-this-safe-to-run) below, including
how to verify the download actually came from this repo's CI.

The tier emoji and today's spend appear in your menu bar (e.g. `🥇 $4.79`).
Turn on **Launch at login** in Settings to have it start with your Mac.

### Or build it yourself

No binary to trust, and no Gatekeeper prompt:

```sh
git clone https://github.com/brunellegrossmann/claude-usage-tracker.git
cd claude-usage-tracker
./install.sh
```

This compiles the app, installs it to `~/Applications/Claude Code Usage.app`,
launches it, and registers it to start at login. Re-run `./install.sh` any time
to rebuild.

## Is this safe to run?

Honest answers, because the install asks you to skip a macOS protection.

**The app is not signed with an Apple Developer ID and is not notarized.** That
costs $99/year and this project does not pay it. Ad-hoc signing carries no
identity, so macOS genuinely cannot tell you who built this. If your policy is
"no unsigned apps", that policy is correct and you should build from source
instead.

**You can still verify the download came from this repo's public CI.** Every
release zip carries a [build provenance
attestation](https://docs.github.com/en/actions/security-guides/using-artifact-attestations):

```sh
gh attestation verify "Claude-Code-Usage-v1.2.0.zip" -R brunellegrossmann/claude-usage-tracker
```

A pass means this exact zip was produced by
[`.github/workflows/release.yml`](.github/workflows/release.yml) from a specific
public commit - not uploaded from someone's laptop. `checksums.txt` in the
release lets you check the bytes too, though a checksum published next to the
file it describes proves little on its own.

**Exactly what leaves your machine.** Two requests, both to GitHub, both
`GET`-only:

| Request | Why |
|---|---|
| `api.github.com/repos/.../releases/latest` | Is there a newer version? At most once every 6 hours. |
| `brunellegrossmann.github.io/.../pricing.json` | Current per-token rates. At most once every 24 hours. |

Nothing is uploaded. No analytics, no crash reporting, no install identifier, no
telemetry, no cookies. Your prompts, projects, and token counts never leave the
machine, and the app has no server to send them to.

**What it reads, and what it never asks for.** It reads
`~/.claude/projects/**/*.jsonl` - your own files in your own home directory -
plus its settings in `UserDefaults`. That needs no macOS permission prompt: no
Full Disk Access, no Accessibility, no Keychain, no camera or microphone, no
listening socket. It writes only its cached price list under
`~/Library/Application Support/`.

**The `xattr -cr` step.** It removes the quarantine flag macOS puts on
downloaded files, which is what makes the Gatekeeper dialog appear. It lowers
your protection for that app. Do it for a build you have verified, not as a
routine habit.

**Updates.** The app tells you when a newer release exists and links to it. It
never downloads or replaces itself; you install the new version yourself.

Every release zip is also published with an Ed25519 signature
(`Claude-Code-Usage-vX.Y.Z.zip.sig`) made with a key held only by the
maintainer, so controlling the download server is not enough to forge a build.
The in-app updater that checks that signature automatically is not shipped yet;
until it is, `gh attestation verify` above is the check to run.

## Updates

The app checks GitHub for a newer release in the background (at most once every
6 hours) and, when one exists, shows a **🔔 Update available** banner at the top
of the popover. Clicking it opens the release page.

To update, download the new zip and replace the app in `/Applications`, or
`git pull && ./install.sh` if you build from source. Verify the download first;
see [Is this safe to run?](#is-this-safe-to-run).

### Cutting a release (maintainer)

See [RELEASING.md](RELEASING.md).

## How it works

1. Recursively scans `~/.claude/projects/**/*.jsonl` (or
   `$CLAUDE_CONFIG_DIR/projects` when that variable relocates your Claude Code
   config).
2. For each assistant message it reads `message.usage` (input, output, cache
   read, and 5-minute / 1-hour cache-write tokens) and `message.model`.
3. Deduplicates records by `message.id | requestId`.
4. Buckets cost by **local** calendar day, then aggregates today / month / 14-day
   views.
5. Refreshes every 60 seconds on a background thread; only files whose
   modification time or size changed are re-parsed.

### Cost basis

Costs are **token-based dollar estimates** - what your usage would cost at
Anthropic's published per-token API rates. This is the same basis tools like
`ccusage` use. If you are on a Max/Pro subscription, treat the numbers as a usage
gauge, not a literal invoice.

## Prices

Rates are not hardcoded into the app you install.
They are published as a small JSON file and read by the app at most once every 24 hours:

```
https://brunellegrossmann.github.io/claude-usage-tracker/pricing.json
```

When Anthropic changes a price, that file changes and every installed app is correct within a day, with no app update and nothing for you to do.
Settings ▸ Pricing shows which rates are in use, when they were last checked, and a **Check for new prices** button.

What the app promises about that fetch:

- **Fetch only.** A plain conditional `GET`. No body, no cookies, no identifiers, nothing about you or your usage. Nothing is ever uploaded.
- **Never fatal.** Unreachable, malformed, or tampered-with feed leaves the last known-good prices in place. It cannot zero out or wildly inflate your numbers.
- **Works offline.** The price list as published at build time is compiled into the app.
- **Version-pinned.** A feed newer than your app understands is refused, not guessed at.

The contract, the schema, and how to change a price are in [`docs/PRICING_FEED.md`](docs/PRICING_FEED.md).
Prices come from [Anthropic's published API rates](https://claude.com/pricing#api).

Each usage record is priced at the rate in effect **on its own timestamp**, so an announced change ("new rate from 26 Aug") leaves earlier days priced correctly instead of retroactively repricing your history.

## Uninstall

```sh
./uninstall.sh
```

(First turn off **Launch at login** in the menu so macOS drops the login-item
registration cleanly.)

## Layout

A SwiftPM package: a thin executable hands off to a library target
(`ClaudeCodeUsageKit`) so the app logic is unit-testable, one file per
type/responsibility.

```
Package.swift
Sources/
  ClaudeCodeUsage/main.swift          # thin executable: NSApplication + makeAppDelegate()
  ClaudeCodeUsageKit/
    App/            # AppDelegate (status item + popover, AppKit) + AppCoordinator (scan loop, AppKit-free)
    Models/         # UsageEntry, Snapshot, TierTheme — plain data
    Pricing/        # published price feed: catalog, validation, 24h refresh, bundled fallback
    Preferences/     # Config — UserDefaults-backed settings
    Services/       # UsageScanner — reads/parses ~/.claude/projects/**/*.jsonl
    ViewModels/      # Tiers, Formatting — pure, unit-tested derivation
    Views/           # SwiftUI popover + Settings window
Tests/
  ClaudeCodeUsageKitTests/            # XCTest: pricing, tiers, formatting, scanner parsing/aggregation
Resources/Info.plist   # bundle metadata (LSUIElement = menu-bar only)
docs/pricing.json      # the published price list (served by GitHub Pages)
docs/PRICING_FEED.md   # the feed's contract and schema
Scripts/embed_pricing.sh  # regenerates the bundled copy of docs/pricing.json
RELEASING.md           # release flow: signing key, tagging, verifying the download
build.sh               # swift build -c release, then wrap the binary in the .app bundle
check.sh               # compile gate + swift test (skips tests without Xcode; CI still runs them)
install.sh             # build + install to ~/Applications + launch
uninstall.sh           # quit + remove
.github/workflows/ci.yml       # swift build --build-tests && swift test on push/PR
.github/workflows/release.yml  # on v* tag: build, zip, sign, attest, publish
```

Run `./check.sh` before rebuilding to catch compile errors and test failures early.

## License

MIT — see [LICENSE](LICENSE).
