import Foundation

// MARK: - Aggregated snapshot the menu renders

struct Snapshot {
    var todayCost: Double = 0
    var monthCost: Double = 0
    var projectedMonthCost: Double = 0
    var averagePerActiveDay: Double = 0
    var busiestDayLabel: String = "—"
    var busiestDayCost: Double = 0
    var costByModelThisMonth: [(name: String, cost: Double)] = []
    var topProjectsToday: [(name: String, cost: Double)] = []
    var last14Days: [DailyTotal] = []
    var hourlyToday: [Double] = Array(repeating: 0, count: 24)
    var inputTokensToday: Int = 0
    var outputTokensToday: Int = 0
    var lastRefresh: Date = Date()
    /// Copied from `Config.monthlyBudgetDollars` at scan time, so the popover
    /// reflects the budget that was active when this snapshot was computed.
    var monthlyBudgetDollars: Double = 1000
}
