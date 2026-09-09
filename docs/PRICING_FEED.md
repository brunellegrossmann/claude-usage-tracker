# Pricing feed contract

`docs/pricing.json` is the price list the app bills with.
It is published over HTTPS by GitHub Pages and read by every installed app at most once every 24 hours:

```
https://brunellegrossmann.github.io/claude-usage-tracker/pricing.json
```

Prices come from [Anthropic's published API rates](https://claude.com/pricing#api).
Editing this file corrects everyone's numbers without shipping an app update.

## One-time setup (maintainer)

The feed is served by GitHub Pages, which must be enabled once:
repo **Settings ▸ Pages ▸ Source: Deploy from a branch**, branch `main`, folder `/docs`.

Until that is done the URL returns 404, every app silently falls back to its bundled prices, and Settings ▸ Pricing shows the failure.
Verify with:

```sh
curl -sSI https://brunellegrossmann.github.io/claude-usage-tracker/pricing.json | head -1
```

## What the app guarantees

These are the properties the code enforces, not intentions.
They exist so a remote file can never silently break or spy on an installed app.

- **Fetch only.** The request is a plain conditional `GET`. It carries no body, no cookies, no identifiers, and nothing about the user or their usage. Nothing is uploaded, ever.
- **Never fatal.** A missing, unreachable, malformed, or hostile feed leaves the previously loaded prices in place. Precedence is bundled < cached < freshly fetched, and a catalog is adopted only after it decodes and passes validation.
- **Works offline.** The feed as published at build time is compiled into the app, so a fresh install with no network prices usage correctly.
- **Bounded.** Rates outside `0 < rate <= 1000` per million tokens are refused as typos.
- **Version-pinned.** A feed declaring a `schemaVersion` higher than the app understands is refused rather than guessed at. Old apps keep working when the contract changes.
- **Visible.** Settings ▸ Pricing states whether the numbers came from the feed or from the bundled defaults, when they were last checked, and what the current rates are.
- **Cheap.** One conditional request per app per day, revalidated with an `ETag`, so an unchanged feed answers `304` with no body.

## Schema (version 1)

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-09-09",
  "source": "https://claude.com/pricing#api",
  "fallbackModelId": "sonnet",
  "defaultCacheMultipliers": { "read": 0.1, "write5m": 1.25, "write1h": 2.0 },
  "models": [
    {
      "id": "sonnet-5",
      "displayName": "Sonnet 5",
      "family": "Sonnet",
      "legacy": false,
      "match": ["sonnet-5", "sonnet5"],
      "periods": [
        { "from": null, "until": null, "inputPerMillion": 2, "outputPerMillion": 10 }
      ]
    }
  ]
}
```

### Top level

| Field | Required | Meaning |
|---|---|---|
| `schemaVersion` | yes | Contract version. Must be `1`. |
| `updatedAt` | yes | Publication date (`YYYY-MM-DD`), shown in Settings. |
| `source` | no | Human-checkable origin of the numbers; linked from Settings. |
| `fallbackModelId` | no | Prices a Claude model no `match` pattern recognises. Omit it and unrecognised models are treated as unpriced rather than guessed. |
| `defaultCacheMultipliers` | no | Cache rates as a multiple of the input rate. Defaults to read 0.1x, 5m write 1.25x, 1h write 2x. |
| `models` | yes | Ordered, non-empty. |

### Model

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable identifier. Referenced by `fallbackModelId`. |
| `displayName` | yes | Shown in Settings ▸ Pricing. |
| `family` | yes | Grouping label for the by-model breakdown (`Opus`, `Sonnet`, …). |
| `legacy` | no | `true` when the entry exists only to price retired models. |
| `match` | yes | Lowercased substrings tested against the model string in the logs. |
| `periods` | yes | Non-empty, non-overlapping price history. |

**Order matters.** The first model whose `match` patterns appear in the log's model string wins.
`claude-sonnet-5` also contains `sonnet`, so `sonnet-5` must be listed before `sonnet`.
Same for `opus-4-1` before `opus`, and `fable-5-1` before `fable`.

### Period

A period is a half-open range `[from, until)`.
Both bounds accept `YYYY-MM-DD` (UTC midnight) or a full ISO 8601 timestamp, and both are optional: `from` omitted means "since forever", `until` omitted means "still current".

| Field | Required | Meaning |
|---|---|---|
| `from`, `until` | no | Range this price applied over. |
| `inputPerMillion`, `outputPerMillion` | yes | USD per million tokens. |
| `cacheReadPerMillion` | no | Overrides the derived cache-read rate. |
| `cacheWrite5mPerMillion`, `cacheWrite1hPerMillion` | no | Override the derived cache-write rates. |

Each usage record is priced at the rates in effect **on its own timestamp**, so history stays correct across a price change.
Usage older than the earliest period is priced at that earliest period: an incomplete history under-reports by a known rate rather than reporting a spurious $0.

## Changing prices

Anthropic announces a change ("new rate from 26 Aug"), so close the current period and open the next one:

```json
"periods": [
  { "until": "2026-08-26", "inputPerMillion": 2, "outputPerMillion": 10 },
  { "from":  "2026-08-26", "inputPerMillion": 3, "outputPerMillion": 15 }
]
```

Both sides of the boundary stay correct, and yesterday's spend does not change retroactively.

Steps:

1. Edit `docs/pricing.json`. Bump `updatedAt`.
2. Run `bash Scripts/embed_pricing.sh` to regenerate the bundled copy.
3. Open a PR. CI validates the feed and fails if the bundled copy is stale.
4. Merge. GitHub Pages serves the new file within about a minute, and every app picks it up within a day (or immediately via Settings ▸ Pricing ▸ Check for new prices).

No app release is needed for a price change.

## Adding a new model

Add an entry **above** the family default so its `match` patterns take precedence, and give it the family's grouping label.
A model with no entry falls back to `fallbackModelId`, which is deliberately the standard Sonnet rate: a new model reports approximately rather than as free.

## Why the numbers are estimates

Costs are what the usage would have cost at published per-token API rates.
On a Max or Pro subscription, read them as a usage gauge, not an invoice.
