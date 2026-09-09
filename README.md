# Claude Code Usage

A native macOS **menu-bar app** that shows what your Claude Code usage costs.
The menu bar shows **today's spend** behind a tier emoji at a glance.
The dropdown adds **month-to-date** (resetting on a configurable day, the 1st by
default), a projected month total, and a detailed breakdown.

```
🥇 $4.79
```

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

- macOS 13 (Ventura) or later.
- Xcode Command Line Tools (for the Swift toolchain): `xcode-select --install`.
  Unit tests need full Xcode (XCTest isn't in the CLT); `check.sh` skips them
  locally without it and they still run in CI.

## Install

```sh
git clone <your-repo-url> claude-code-usage   # or just use this folder
cd claude-code-usage
./install.sh
```

This compiles the app, installs it to `~/Applications/Claude Code Usage.app`,
launches it, and registers it to start at login. Re-run `./install.sh` any time
to rebuild and update.

## Updates

The app checks GitHub for a newer release in the background (at most once every
6 hours) and, when one exists, shows a **🔔 Update available** banner at the top
of the popover.
Clicking it opens the latest release page.
To update, pull and rebuild:

```sh
git pull && ./install.sh
```

### Cutting a release (maintainer)

Releases are the version the app compares against, published by the
`release` GitHub Actions workflow when a `v*` tag is pushed:

```sh
git tag v1.1.0
git push origin v1.1.0
```

The workflow builds the app (proving the tag compiles), stamps the version, and
publishes a GitHub Release with auto-generated notes.
No binary is attached - the app is ad-hoc signed, so distribution stays
build-from-source.

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
build.sh               # swift build -c release, then wrap the binary in the .app bundle
check.sh               # compile gate + swift test (skips tests without Xcode; CI still runs them)
install.sh             # build + install to ~/Applications + launch
uninstall.sh           # quit + remove
.github/workflows/ci.yml  # swift build --build-tests && swift test on push/PR
```

Run `./check.sh` before rebuilding to catch compile errors and test failures early.

## License

MIT — see [LICENSE](LICENSE).
