import XCTest
@testable import ClaudeCodeUsageKit

final class PricingTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let anyDate = Date(timeIntervalSince1970: 0)

    func test_rates_matches_model_family_by_substring() {
        XCTAssertEqual(Pricing.rates(forModel: "claude-opus-4-8", usedOn: anyDate)?.inputPerToken, Pricing.opus.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-sonnet-4-6", usedOn: anyDate)?.inputPerToken, Pricing.sonnet.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-haiku-4-5", usedOn: anyDate)?.inputPerToken, Pricing.haiku.inputPerToken)
        XCTAssertEqual(Pricing.rates(forModel: "claude-fable-5", usedOn: anyDate)?.inputPerToken, Pricing.fable.inputPerToken)
    }

    func test_rates_falls_back_to_sonnet_for_unknown_claude_model() {
        XCTAssertEqual(Pricing.rates(forModel: "claude-mystery-9", usedOn: anyDate)?.inputPerToken, Pricing.sonnet.inputPerToken)
    }

    func test_rates_returns_nil_for_non_claude_synthetic_entries() {
        XCTAssertNil(Pricing.rates(forModel: "<synthetic>", usedOn: anyDate))
    }

    func test_rates_matching_is_case_insensitive() {
        XCTAssertEqual(Pricing.rates(forModel: "CLAUDE-OPUS-4-8", usedOn: anyDate)?.inputPerToken, Pricing.opus.inputPerToken)
    }

    func test_sonnet5_uses_introductory_price_before_reversion_date() {
        let rates = Pricing.rates(forModel: "claude-sonnet-5", usedOn: date(2026, 7, 10))
        XCTAssertEqual(rates?.inputPerToken, Pricing.sonnet5Introductory.inputPerToken)
        XCTAssertEqual(rates?.outputPerToken, Pricing.sonnet5Introductory.outputPerToken)
    }

    func test_sonnet5_uses_standard_price_on_reversion_date() {
        let rates = Pricing.rates(forModel: "claude-sonnet-5", usedOn: date(2026, 9, 1))
        XCTAssertEqual(rates?.inputPerToken, Pricing.sonnet.inputPerToken)
        XCTAssertEqual(rates?.outputPerToken, Pricing.sonnet.outputPerToken)
    }

    func test_sonnet_4_5_keeps_standard_price_before_reversion_date() {
        let rates = Pricing.rates(forModel: "claude-sonnet-4-5", usedOn: date(2026, 7, 10))
        XCTAssertEqual(rates?.inputPerToken, Pricing.sonnet.inputPerToken)
    }

    func test_isBillable_true_for_claude_model_and_false_for_synthetic() {
        XCTAssertTrue(Pricing.isBillable("claude-sonnet-5"))
        XCTAssertFalse(Pricing.isBillable("<synthetic>"))
    }
}
