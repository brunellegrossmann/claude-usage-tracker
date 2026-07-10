import Foundation

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
    static let sonnet5Introductory = ModelRates.from(inputPerMillion: 2, outputPerMillion: 10)
    static let haiku = ModelRates.from(inputPerMillion: 1, outputPerMillion: 5)
    static let fable = ModelRates.from(inputPerMillion: 10, outputPerMillion: 50)

    /// Sonnet 5 launched on introductory pricing ($2/$10 per MTok); usage on or
    /// after this date reverts to standard Sonnet pricing ($3/$15 per MTok).
    static let sonnet5IntroductoryEnd: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Whether usage for this model is billed. Independent of the usage date.
    static func isBillable(_ model: String) -> Bool {
        family(forModel: model) != nil
    }

    /// Rates for a model at the time the usage occurred. Sonnet 5 is priced by
    /// date because its introductory rate reverts on `sonnet5IntroductoryEnd`.
    static func rates(forModel model: String, usedOn date: Date) -> ModelRates? {
        switch family(forModel: model) {
        case .opus: return opus
        case .sonnet: return sonnet
        case .sonnet5: return date < sonnet5IntroductoryEnd ? sonnet5Introductory : sonnet
        case .haiku: return haiku
        case .fable: return fable
        case .none: return nil
        }
    }

    private enum Family { case opus, sonnet, sonnet5, haiku, fable }

    /// Match by family substring; unknown Claude models priced as Sonnet (a safe middle).
    private static func family(forModel model: String) -> Family? {
        let m = model.lowercased()
        if m.contains("opus") { return .opus }
        if m.contains("sonnet") {
            return m.contains("sonnet-5") || m.contains("sonnet5") ? .sonnet5 : .sonnet
        }
        if m.contains("haiku") { return .haiku }
        if m.contains("fable") || m.contains("mythos") { return .fable }
        // Skip non-billable synthetic entries (e.g. "<synthetic>").
        if m.contains("claude") { return .sonnet }
        return nil
    }
}
