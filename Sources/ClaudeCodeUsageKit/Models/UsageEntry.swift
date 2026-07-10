import Foundation

// MARK: - Usage record

struct UsageEntry {
    let dedupeKey: String
    let timestamp: Date
    let projectName: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int

    var cost: Double {
        guard let r = Pricing.rates(forModel: model, usedOn: timestamp) else { return 0 }
        return Double(inputTokens) * r.inputPerToken
            + Double(outputTokens) * r.outputPerToken
            + Double(cacheReadTokens) * r.cacheReadPerToken
            + Double(cacheWrite5mTokens) * r.cacheWrite5mPerToken
            + Double(cacheWrite1hTokens) * r.cacheWrite1hPerToken
    }

    var totalInputLikeTokens: Int {
        inputTokens + cacheReadTokens + cacheWrite5mTokens + cacheWrite1hTokens
    }
}

// MARK: - One day's aggregated cost (for the 14-day sparkline)

struct DailyTotal {
    let dayStart: Date
    var cost: Double
}
