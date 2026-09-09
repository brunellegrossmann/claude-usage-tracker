import Foundation
@testable import ClaudeCodeUsageKit

extension UsageEntry {
    /// A usage entry with sensible defaults; override only the fields a test
    /// cares about, keeping the many-field memberwise init out of every test.
    static func stub(
        dedupeKey: String = "msg-1|req-1",
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        projectName: String = "demo-project",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0
    ) -> UsageEntry {
        UsageEntry(
            dedupeKey: dedupeKey, timestamp: timestamp, projectName: projectName, model: model,
            inputTokens: inputTokens, outputTokens: outputTokens, cacheReadTokens: cacheReadTokens,
            cacheWrite5mTokens: cacheWrite5mTokens, cacheWrite1hTokens: cacheWrite1hTokens)
    }
}

extension PricingCatalog {
    /// The prices shipped with the app. Tests assert against these so a price
    /// change shows up as a failing expectation rather than a silent drift.
    static let bundledForTests = BundledPricingFeed.catalog

    /// Builds a catalog from feed JSON, failing the test when it is rejected.
    static func fromFeedJSON(_ json: String) throws -> PricingCatalog {
        try PricingCatalogDecoder.decode(Data(json.utf8), origin: .bundled)
    }
}
