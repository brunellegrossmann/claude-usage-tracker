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

1. Recursively scans `~/.claude/projects/**/*.jsonl`.
2. For each assistant message it reads `message.usage` (input, output, cache
   read, and 5-minute / 1-hour cache-write tokens) and `message.model`.
3. Deduplicates records by `message.id | requestId`.
4. Buckets cost by **local** calendar day, then aggregates today / month / 14-day
   views.
5. Refreshes every 60 seconds on a background thread; only files whose
   modification time or size changed are re-parsed.

### Cost basis

Costs are **token-based dollar estimates** — what your usage would cost at
Anthropic's published per-token API rates. This is the same basis tools like
`ccusage` use. If you are on a Max/Pro subscription, treat the numbers as a usage
gauge, not a literal invoice.

## Updating prices

Rates are hardcoded in the `Pricing` enum in
[`Sources/ClaudeCodeUsageKit/Pricing/Pricing.swift`](Sources/ClaudeCodeUsageKit/Pricing/Pricing.swift)
(per million tokens; cache write = 1.25× / 2× input, cache read = 0.1× input).
When Anthropic changes pricing, edit that enum and re-run `./install.sh`.

| Model                | Input | Output |
|----------------------|-------|--------|
| Opus 4.8             | $5    | $25    |
| Sonnet 5 (intro)     | $2    | $10    |
| Sonnet 4.6           | $3    | $15    |
| Haiku 4.5            | $1    | $5     |
| Fable 5              | $10   | $50    |

Sonnet 5 is on introductory pricing ($2/$10) for usage before 2026-09-01; entries
on or after that date are priced at the standard Sonnet rate ($3/$15) automatically,
by the entry's own timestamp.

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
    Pricing/        # per-token USD rates by model family
    Preferences/     # Config — UserDefaults-backed settings
    Services/       # UsageScanner — reads/parses ~/.claude/projects/**/*.jsonl
    ViewModels/      # Tiers, Formatting — pure, unit-tested derivation
    Views/           # SwiftUI popover + Settings window
Tests/
  ClaudeCodeUsageKitTests/            # XCTest: pricing, tiers, formatting, scanner parsing/aggregation
Resources/Info.plist   # bundle metadata (LSUIElement = menu-bar only)
build.sh               # swift build -c release, then wrap the binary in the .app bundle
check.sh               # compile gate + swift test (skips tests without Xcode; CI still runs them)
install.sh             # build + install to ~/Applications + launch
uninstall.sh           # quit + remove
.github/workflows/ci.yml  # swift build --build-tests && swift test on push/PR
```

Run `./check.sh` before rebuilding to catch compile errors and test failures early.

## License

MIT — see [LICENSE](LICENSE).
