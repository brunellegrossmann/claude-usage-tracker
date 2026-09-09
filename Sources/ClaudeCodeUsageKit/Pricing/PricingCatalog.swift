import Foundation

// MARK: - Pricing catalog (decoded from the pricing feed contract)

/// Per-token USD rates for one model over one price period.
struct ModelRates: Equatable {
    let inputPerToken: Double
    let outputPerToken: Double
    let cacheReadPerToken: Double
    let cacheWrite5mPerToken: Double
    let cacheWrite1hPerToken: Double
}

/// Where a catalog came from, so the UI can show the numbers' provenance
/// instead of silently changing what a user is billed.
enum PricingCatalogOrigin: Equatable {
    /// Compiled into the app from `docs/pricing.json` at build time.
    case bundled
    /// Fetched from the published feed (or replayed from its on-disk cache).
    case feed(fetchedAt: Date)
}

/// A validated snapshot of "what each model costs, when". Immutable: a feed
/// refresh produces a new catalog rather than mutating this one.
struct PricingCatalog: Equatable {
    /// Feed schema this app understands. A feed declaring a higher version is
    /// rejected, so a future breaking contract can never mis-price an old app.
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    /// Publication date as the feed states it, e.g. "2026-09-09". Shown to users.
    let updatedAt: String
    /// Human-checkable origin of the numbers, e.g. Anthropic's pricing page.
    let source: String?
    let origin: PricingCatalogOrigin
    let models: [ModelPricing]
    /// Model whose rates price an unrecognised Claude model. Optional: without
    /// it, unrecognised models are treated as unpriced rather than guessed.
    let fallbackModelId: String?
    let cacheMultipliers: CacheMultipliers

    private var fallbackModel: ModelPricing? {
        guard let fallbackModelId else { return nil }
        return models.first { $0.id == fallbackModelId }
    }

    /// Rates for `model` as priced at the time the usage happened, or nil when
    /// the model isn't billable (synthetic entries, unknown non-Claude models).
    func rates(forModel model: String, usedOn date: Date) -> ModelRates? {
        guard let pricing = pricing(forModel: model) else { return nil }
        return pricing.rates(on: date, multipliers: cacheMultipliers)
    }

    /// Whether usage for this model costs money. Independent of the usage date.
    func isBillable(_ model: String) -> Bool {
        pricing(forModel: model) != nil
    }

    /// Grouping label for the by-model breakdown ("Opus", "Sonnet", …), or the
    /// raw model string when the catalog doesn't recognise it.
    func displayFamily(forModel model: String) -> String {
        pricing(forModel: model)?.family ?? model
    }

    /// First model whose `match` patterns appear in `model`, so the feed's
    /// order decides specificity ("sonnet-5" must precede "sonnet"). Falls back
    /// to `fallbackModelId` only for strings that name a Claude model, so
    /// synthetic entries like "<synthetic>" stay unpriced.
    private func pricing(forModel model: String) -> ModelPricing? {
        let needle = model.lowercased()
        if let matched = models.first(where: { pricing in
            pricing.match.contains { needle.contains($0) }
        }) {
            return matched
        }
        return needle.contains("claude") ? fallbackModel : nil
    }
}

/// Cache-token rates are usually a fixed multiple of the input rate; a period
/// may still state any of them explicitly when a model deviates.
struct CacheMultipliers: Equatable {
    let read: Double
    let write5m: Double
    let write1h: Double

    static let anthropicDefaults = CacheMultipliers(read: 0.1, write5m: 1.25, write1h: 2.0)
}

/// One model (or one group of identically-priced models) and its price history.
struct ModelPricing: Equatable {
    let id: String
    let displayName: String
    /// Grouping label for the by-model breakdown.
    let family: String
    /// True when this entry exists only to price retired models.
    let legacy: Bool
    /// Lowercased substrings matched against the model string from the logs.
    let match: [String]
    /// Price periods, ordered oldest first and non-overlapping.
    let periods: [PricePeriod]

    /// Rates in effect on `date`. Usage older than the earliest period is
    /// priced at that earliest period: an incomplete price history should
    /// under-report by a known rate, never report a spurious $0.
    func rates(on date: Date, multipliers: CacheMultipliers) -> ModelRates? {
        let period = periods.first { $0.covers(date) } ?? periods.first
        return period?.rates(multipliers: multipliers)
    }
}

/// A price that held over a half-open time range: `[from, until)`.
struct PricePeriod: Equatable {
    /// First instant this price applies. Nil means "since forever".
    let from: Date?
    /// First instant this price no longer applies. Nil means "still current".
    let until: Date?
    let inputPerMillion: Double
    let outputPerMillion: Double
    /// Explicit cache rates; nil derives them from the input rate.
    let cacheReadPerMillion: Double?
    let cacheWrite5mPerMillion: Double?
    let cacheWrite1hPerMillion: Double?

    func covers(_ date: Date) -> Bool {
        if let from, date < from { return false }
        if let until, date >= until { return false }
        return true
    }

    func rates(multipliers: CacheMultipliers) -> ModelRates {
        let perToken = { (perMillion: Double) in perMillion / 1_000_000 }
        return ModelRates(
            inputPerToken: perToken(inputPerMillion),
            outputPerToken: perToken(outputPerMillion),
            cacheReadPerToken: perToken(cacheReadPerMillion ?? inputPerMillion * multipliers.read),
            cacheWrite5mPerToken: perToken(cacheWrite5mPerMillion ?? inputPerMillion * multipliers.write5m),
            cacheWrite1hPerToken: perToken(cacheWrite1hPerMillion ?? inputPerMillion * multipliers.write1h)
        )
    }
}
