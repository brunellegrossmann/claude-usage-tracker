import XCTest
@testable import ClaudeCodeUsageKit

/// Covers the prices the app ships with, and the rules that map a model string
/// from the logs onto a rate.
final class PricingTests: XCTestCase {
    private let catalog = PricingCatalog.bundledForTests
    private let anyDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Shipped rates

    func test_shipped_rates_match_anthropics_published_prices() {
        let expected: [(model: String, input: Double, output: Double)] = [
            ("claude-opus-5", 5, 25),
            ("claude-opus-4-8", 5, 25),
            ("claude-opus-4-1-20250805", 15, 75),
            ("claude-sonnet-5", 2, 10),
            ("claude-sonnet-4-6", 3, 15),
            ("claude-sonnet-4-5-20250929", 3, 15),
            ("claude-haiku-4-5-20251001", 1, 5),
            ("claude-fable-5-1", 10, 50),
            ("claude-fable-5", 10, 50),
        ]
        for expectation in expected {
            let rates = catalog.rates(forModel: expectation.model, usedOn: anyDate)
            XCTAssertEqual(rates?.inputPerToken, expectation.input / 1_000_000,
                           "input rate for \(expectation.model)")
            XCTAssertEqual(rates?.outputPerToken, expectation.output / 1_000_000,
                           "output rate for \(expectation.model)")
        }
    }

    func test_newer_model_generation_is_priced_before_the_family_default() {
        // "claude-sonnet-5" also contains "sonnet"; feed order must win.
        XCTAssertEqual(catalog.rates(forModel: "claude-sonnet-5", usedOn: anyDate)?.inputPerToken,
                       2 / 1_000_000)
        XCTAssertEqual(catalog.rates(forModel: "claude-opus-4-1", usedOn: anyDate)?.inputPerToken,
                       15 / 1_000_000)
    }

    func test_cache_rates_are_derived_from_input_unless_stated() {
        // Haiku states no 1h write rate, so it comes from the 2x multiplier.
        let haiku = catalog.rates(forModel: "claude-haiku-4-5", usedOn: anyDate)
        XCTAssertEqual(haiku?.cacheWrite1hPerToken, 2 / 1_000_000)
        // Fable 5.1's cache read is cheaper than the usual 0.1x, so it is stated.
        let fable = catalog.rates(forModel: "claude-fable-5-1", usedOn: anyDate)
        XCTAssertEqual(fable?.cacheReadPerToken, 0.25 / 1_000_000)
    }

    func test_model_matching_ignores_case() {
        XCTAssertEqual(catalog.rates(forModel: "CLAUDE-OPUS-5", usedOn: anyDate)?.inputPerToken,
                       5 / 1_000_000)
    }

    func test_unrecognised_claude_model_is_priced_as_the_fallback() {
        XCTAssertEqual(catalog.rates(forModel: "claude-mystery-9", usedOn: anyDate)?.inputPerToken,
                       catalog.rates(forModel: "claude-sonnet-4-6", usedOn: anyDate)?.inputPerToken)
    }

    func test_synthetic_entry_is_not_billable() {
        XCTAssertNil(catalog.rates(forModel: "<synthetic>", usedOn: anyDate))
        XCTAssertFalse(catalog.isBillable("<synthetic>"))
        XCTAssertTrue(catalog.isBillable("claude-sonnet-5"))
    }

    func test_breakdown_groups_models_by_family() {
        XCTAssertEqual(catalog.displayFamily(forModel: "claude-opus-4-1"), "Opus")
        XCTAssertEqual(catalog.displayFamily(forModel: "claude-sonnet-5"), "Sonnet")
        XCTAssertEqual(catalog.displayFamily(forModel: "<synthetic>"), "<synthetic>")
    }

    // MARK: Price periods

    private let periodFeed = """
    {
      "schemaVersion": 1, "updatedAt": "2026-09-09", "models": [
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [
            { "until": "2026-08-26", "inputPerMillion": 2, "outputPerMillion": 10 },
            { "from": "2026-08-26", "inputPerMillion": 3, "outputPerMillion": 15 }
        ]}
      ]
    }
    """

    func test_usage_is_priced_at_the_rate_in_effect_that_day() throws {
        let catalog = try PricingCatalog.fromFeedJSON(periodFeed)
        XCTAssertEqual(catalog.rates(forModel: "demo", usedOn: day("2026-08-25"))?.inputPerToken,
                       2 / 1_000_000)
        XCTAssertEqual(catalog.rates(forModel: "demo", usedOn: day("2026-08-26"))?.inputPerToken,
                       3 / 1_000_000)
    }

    func test_usage_older_than_the_price_history_uses_the_earliest_known_rate() throws {
        let catalog = try PricingCatalog.fromFeedJSON("""
        {
          "schemaVersion": 1, "updatedAt": "2026-09-09", "models": [
            { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [
                { "from": "2026-08-26", "inputPerMillion": 3, "outputPerMillion": 15 }
            ]}
          ]
        }
        """)
        XCTAssertEqual(catalog.rates(forModel: "demo", usedOn: day("2020-01-01"))?.inputPerToken,
                       3 / 1_000_000)
    }

    // MARK: Cost

    func test_entry_cost_sums_every_token_kind_at_its_own_rate() {
        let entry = UsageEntry.stub(
            timestamp: anyDate, model: "claude-sonnet-4-6",
            inputTokens: 1_000_000, outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000, cacheWrite5mTokens: 1_000_000, cacheWrite1hTokens: 1_000_000)
        // $3 input + $15 output + $0.30 read + $3.75 write-5m + $6 write-1h.
        XCTAssertEqual(entry.cost(using: catalog), 28.05, accuracy: 0.0001)
    }

    func test_entry_cost_is_zero_for_a_model_the_catalog_does_not_price() {
        let entry = UsageEntry.stub(model: "<synthetic>", inputTokens: 1_000_000)
        XCTAssertEqual(entry.cost(using: catalog), 0)
    }

    private func day(_ text: String) -> Date {
        guard let date = parseFeedDate(text) else {
            XCTFail("bad test date \(text)")
            return Date()
        }
        return date
    }
}
