import XCTest
@testable import ClaudeCodeUsageKit

final class UsageScannerTests: XCTestCase {

    // MARK: parseLine

    func test_parse_line_extracts_tokens_and_model() {
        let line = """
        {"timestamp":"2026-01-15T10:00:00.000Z","cwd":"/Users/me/demo","message":{"id":"msg-1","model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":10}}}
        """
        let entry = UsageScanner.parseLine(line, fallbackProjectName: "fallback")
        XCTAssertEqual(entry?.inputTokens, 100)
        XCTAssertEqual(entry?.outputTokens, 50)
        XCTAssertEqual(entry?.cacheReadTokens, 10)
        XCTAssertEqual(entry?.projectName, "demo")
        XCTAssertEqual(entry?.model, "claude-sonnet-4-6")
    }

    func test_parse_line_falls_back_to_project_name_when_cwd_missing() {
        let line = """
        {"timestamp":"2026-01-15T10:00:00.000Z","message":{"id":"msg-1","model":"claude-sonnet-4-6","usage":{"input_tokens":1}}}
        """
        let entry = UsageScanner.parseLine(line, fallbackProjectName: "fallback")
        XCTAssertEqual(entry?.projectName, "fallback")
    }

    func test_parse_line_reads_5m_and_1h_cache_write_tokens() {
        let line = """
        {"timestamp":"2026-01-15T10:00:00.000Z","message":{"id":"msg-1","model":"claude-opus-4-8","usage":{"cache_creation":{"ephemeral_5m_input_tokens":7,"ephemeral_1h_input_tokens":3}}}}
        """
        let entry = UsageScanner.parseLine(line, fallbackProjectName: "fallback")
        XCTAssertEqual(entry?.cacheWrite5mTokens, 7)
        XCTAssertEqual(entry?.cacheWrite1hTokens, 3)
    }

    func test_parse_line_skips_non_billable_synthetic_entries() {
        let line = """
        {"timestamp":"2026-01-15T10:00:00.000Z","message":{"id":"msg-1","model":"<synthetic>","usage":{"input_tokens":1}}}
        """
        XCTAssertNil(UsageScanner.parseLine(line, fallbackProjectName: "fallback"))
    }

    func test_parse_line_skips_malformed_json() {
        XCTAssertNil(UsageScanner.parseLine("not json", fallbackProjectName: "fallback"))
    }

    // MARK: resolveProjectsDirectory

    private let home = URL(fileURLWithPath: "/Users/test")

    func test_resolve_projects_directory_defaults_to_dot_claude_when_env_unset() {
        let directory = UsageScanner.resolveProjectsDirectory(home: home, environment: [:])
        XCTAssertEqual(directory.path, "/Users/test/.claude/projects")
    }

    func test_resolve_projects_directory_honors_claude_config_dir_override() {
        let directory = UsageScanner.resolveProjectsDirectory(
            home: home, environment: ["CLAUDE_CONFIG_DIR": "/opt/claude-config"])
        XCTAssertEqual(directory.path, "/opt/claude-config/projects")
    }

    func test_resolve_projects_directory_expands_leading_tilde_in_override() {
        let directory = UsageScanner.resolveProjectsDirectory(
            home: home, environment: ["CLAUDE_CONFIG_DIR": "~/work/.claude"])
        XCTAssertEqual(directory.path, "/Users/test/work/.claude/projects")
    }

    func test_resolve_projects_directory_ignores_blank_override() {
        let directory = UsageScanner.resolveProjectsDirectory(
            home: home, environment: ["CLAUDE_CONFIG_DIR": "   "])
        XCTAssertEqual(directory.path, "/Users/test/.claude/projects")
    }

    // MARK: cycleStart

    func test_cycle_start_on_reset_day_one_matches_calendar_month() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let start = UsageScanner.cycleStart(for: date, resetDay: 1, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: start),
                        DateComponents(year: 2026, month: 3, day: 1))
    }

    func test_cycle_start_before_reset_day_falls_back_to_previous_month() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let start = UsageScanner.cycleStart(for: date, resetDay: 15, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 15)
    }

    func test_cycle_start_on_or_after_reset_day_uses_current_month() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let start = UsageScanner.cycleStart(for: date, resetDay: 15, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    // MARK: aggregate

    func test_aggregate_sums_todays_cost_and_dedupes_by_key() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            UsageEntry.stub(dedupeKey: "a", timestamp: now, model: "claude-sonnet-4-6", inputTokens: 1_000_000),
            UsageEntry.stub(dedupeKey: "a", timestamp: now, model: "claude-sonnet-4-6", inputTokens: 1_000_000),
        ]
        let snapshot = UsageScanner.aggregate(entries: entries, now: now, billingCycleResetDay: 1, monthlyBudgetDollars: 1000)
        XCTAssertEqual(snapshot.todayCost, 3.0, accuracy: 0.0001) // 1M sonnet input tokens @ $3/M, counted once
    }

    func test_aggregate_excludes_entries_before_the_billing_cycle_start() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let beforeCycle = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let entries = [UsageEntry.stub(dedupeKey: "old", timestamp: beforeCycle, model: "claude-sonnet-4-6", inputTokens: 1_000_000)]
        let snapshot = UsageScanner.aggregate(entries: entries, now: now, billingCycleResetDay: 15,
                                               monthlyBudgetDollars: 1000, calendar: calendar)
        XCTAssertEqual(snapshot.monthCost, 0)
    }

    func test_aggregate_copies_monthly_budget_into_snapshot() {
        let snapshot = UsageScanner.aggregate(entries: [], now: Date(), billingCycleResetDay: 1, monthlyBudgetDollars: 250)
        XCTAssertEqual(snapshot.monthlyBudgetDollars, 250)
    }

    func test_pace_average_counts_only_days_with_spend() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 9))!
        let entries = [
            UsageEntry.stub(dedupeKey: "d1", timestamp: day1, model: "claude-sonnet-4-6", inputTokens: 1_000_000), // $3
            UsageEntry.stub(dedupeKey: "d2", timestamp: day2, model: "claude-sonnet-4-6", inputTokens: 3_000_000), // $9
        ]
        let snapshot = UsageScanner.aggregate(entries: entries, now: now, billingCycleResetDay: 1,
                                               monthlyBudgetDollars: 1000, calendar: calendar)
        // Two active days ($3, $9); days with no spend are not in the divisor → avg = $6.
        XCTAssertEqual(snapshot.averagePerActiveDay, 6.0, accuracy: 0.0001)
    }

    func test_projection_extrapolates_over_working_days_only() {
        let calendar = Calendar(identifier: .gregorian)
        let workingDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 9))!
        // July 2026 (Wed 1st): 7 Mon–Fri days elapsed through the 9th, 23 in the month.
        let entries = [
            UsageEntry.stub(dedupeKey: "m", timestamp: workingDay, model: "claude-sonnet-4-6", inputTokens: 7_000_000), // $21
        ]
        let snapshot = UsageScanner.aggregate(entries: entries, now: now, billingCycleResetDay: 1,
                                               monthlyBudgetDollars: 1000, workingDays: [2, 3, 4, 5, 6],
                                               calendar: calendar)
        XCTAssertEqual(snapshot.monthCost, 21.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.projectedMonthCost, 69.0, accuracy: 0.0001) // 21 / 7 * 23
    }
}
