import XCTest
@testable import ClaudeCodeUsageKit

final class TiersTests: XCTestCase {
    private let theme = TierTheme(id: "t", name: "Test", steps: [
        TierStep(name: "Warmup", icon: "", unlockAtDollars: 0),
        TierStep(name: "Bronze", icon: "🥉", unlockAtDollars: 10),
        TierStep(name: "Gold", icon: "🥇", unlockAtDollars: 50),
    ])

    func test_current_returns_highest_step_reached() {
        XCTAssertEqual(Tiers.current(forSpend: 0, in: theme).name, "Warmup")
        XCTAssertEqual(Tiers.current(forSpend: 15, in: theme).name, "Bronze")
        XCTAssertEqual(Tiers.current(forSpend: 100, in: theme).name, "Gold")
    }

    func test_current_sorts_unordered_steps_by_threshold() {
        let shuffled = TierTheme(id: "t", name: "Test", steps: [
            TierStep(name: "Gold", icon: "🥇", unlockAtDollars: 50),
            TierStep(name: "Warmup", icon: "", unlockAtDollars: 0),
            TierStep(name: "Bronze", icon: "🥉", unlockAtDollars: 10),
        ])
        XCTAssertEqual(Tiers.current(forSpend: 15, in: shuffled).name, "Bronze")
    }

    func test_next_returns_step_above_current_spend() {
        XCTAssertEqual(Tiers.next(forSpend: 5, in: theme)?.name, "Bronze")
    }

    func test_next_returns_nil_at_top_step() {
        XCTAssertNil(Tiers.next(forSpend: 50, in: theme))
    }

    func test_current_falls_back_to_warmup_when_theme_has_no_steps() {
        let empty = TierTheme(id: "empty", name: "Empty", steps: [])
        XCTAssertEqual(Tiers.current(forSpend: 42, in: empty).name, "Warmup")
    }
}
