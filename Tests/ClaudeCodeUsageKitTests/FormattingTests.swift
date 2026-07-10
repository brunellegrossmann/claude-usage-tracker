import XCTest
@testable import ClaudeCodeUsageKit

final class FormattingTests: XCTestCase {
    func test_format_money_shows_two_decimals_with_dollar_sign() {
        XCTAssertEqual(formatMoney(4.5), "$4.50")
        XCTAssertEqual(formatMoney(0), "$0.00")
    }

    func test_format_tokens_abbreviates_thousands_and_millions() {
        XCTAssertEqual(formatTokens(999), "999")
        XCTAssertEqual(formatTokens(12_345), "12K")
        XCTAssertEqual(formatTokens(3_200_000), "3.2M")
    }
}
