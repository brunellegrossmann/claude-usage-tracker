// MARK: - Pricing (USD per token; from Anthropic published rates)

struct ModelRates {
    let inputPerToken: Double
    let outputPerToken: Double
    let cacheReadPerToken: Double
    let cacheWrite5mPerToken: Double
    let cacheWrite1hPerToken: Double

    /// perMillion: input, output. Cache derived from standard multipliers
    /// (read 0.1x input, write-5m 1.25x input, write-1h 2x input).
    static func from(inputPerMillion: Double, outputPerMillion: Double) -> ModelRates {
        ModelRates(
            inputPerToken: inputPerMillion / 1_000_000,
            outputPerToken: outputPerMillion / 1_000_000,
            cacheReadPerToken: inputPerMillion * 0.10 / 1_000_000,
            cacheWrite5mPerToken: inputPerMillion * 1.25 / 1_000_000,
            cacheWrite1hPerToken: inputPerMillion * 2.0 / 1_000_000
        )
    }
}

enum Pricing {
    static let opus = ModelRates.from(inputPerMillion: 5, outputPerMillion: 25)
    static let sonnet = ModelRates.from(inputPerMillion: 3, outputPerMillion: 15)
    static let haiku = ModelRates.from(inputPerMillion: 1, outputPerMillion: 5)
    static let fable = ModelRates.from(inputPerMillion: 10, outputPerMillion: 50)

    /// Match by family substring; unknown models priced as Sonnet (a safe middle).
    static func rates(forModel model: String) -> ModelRates? {
        let m = model.lowercased()
        if m.contains("opus") { return opus }
        if m.contains("sonnet") { return sonnet }
        if m.contains("haiku") { return haiku }
        if m.contains("fable") || m.contains("mythos") { return fable }
        // Skip non-billable synthetic entries (e.g. "<synthetic>").
        if m.contains("claude") { return sonnet }
        return nil
    }
}
