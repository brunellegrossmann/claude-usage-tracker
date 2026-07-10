import XCTest
@testable import ClaudeCodeUsageKit

final class PricingTests: XCTestCase {
    func test_rates_matches_model_family_by_substring() {
        XCTAssertEqual(Pricing.rates(forModel: "claude-opus-4-8")?.inputPerToken, Pricing.opus.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-sonnet-4-6")?.inputPerToken, Pricing.sonnet.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-haiku-4-5")?.inputPerToken, Pricing.haiku.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-fable-5")?.inputPerToken, Pricing.fable.inputPerToken)
    }

    func test_rates_falls_back_to_sonnet_for_unknown_claude_model() {
        XCTAssertEqual(Pricing.rates(forModel: "claude-mystery-9")?.inputPerToken, Pricing.sonnet.inputPerToken)
    }

    func test_rates_returns_nil_for_non_claude_synthetic_entries() {
        XCTAssertNil(Pricing.rates(forModel: "<synthetic>"))
    }

    func test_rates_matching_is_case_insensitive() {
        XCTAssertEqual(Pricing.rates(forModel: "CLAUDE-OPUS-4-8")?.inputPerToken, Pricing.opus.inputPerToken)
    }
}
