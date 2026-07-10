import Foundation

// MARK: - Settings (UserDefaults-backed configuration)

enum PlanTier: String, CaseIterable, Codable {
    case pro, team, enterprise

    var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        }
    }
}

/// Preference storage for everything the Settings window edits. Read from
/// UserDefaults on every access (so Settings edits apply without a restart),
/// each with a sensible default. Settable directly, or via `defaults write
/// com.local.claudecodeusage <key> ...`.
enum Config {
    /// Which Anthropic plan you're on. Informational only today (shown in
    /// Settings and the status-item tooltip) — pricing already uses the
    /// published per-token API rates regardless of plan.
    static var planTier: PlanTier {
        get { PlanTier(rawValue: UserDefaults.standard.string(forKey: "planTier") ?? "") ?? .enterprise }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "planTier") }
    }

    /// Self-imposed monthly spend cap, shown as a progress bar in "THIS MONTH".
    static var monthlyBudgetDollars: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "monthlyBudgetDollars")
            return stored > 0 ? stored : 1000
        }
        set { UserDefaults.standard.set(max(newValue, 0), forKey: "monthlyBudgetDollars") }
    }

    /// Day of the month the spend cycle resets. Clamped to 1...28 so every
    /// month (including February) has that day. Default 1 reproduces the
    /// previous hardcoded calendar-month behaviour exactly.
    static var billingCycleResetDay: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "billingCycleResetDay")
            return stored > 0 ? min(stored, 28) : 1
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), 28), forKey: "billingCycleResetDay") }
    }

    /// Weekdays the month projection extrapolates over (Calendar weekday numbers:
    /// 1 = Sunday ... 7 = Saturday). Defaults to Monday–Friday, so days you don't
    /// work don't inflate the projected total. An empty selection falls back to
    /// the default.
    static var workingDays: Set<Int> {
        get {
            let stored = (UserDefaults.standard.array(forKey: "workingDays") as? [Int]) ?? []
            return stored.isEmpty ? [2, 3, 4, 5, 6] : Set(stored)
        }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "workingDays") }
    }

    /// `TierTheme.id` of the ladder currently shown in the menu bar and popover.
    static var activeTierThemeId: String {
        get { UserDefaults.standard.string(forKey: "activeTierThemeId") ?? defaultTierThemes[0].id }
        set { UserDefaults.standard.set(newValue, forKey: "activeTierThemeId") }
    }

    /// Every available ladder, editable from Settings > Tier Theme. Seeded
    /// with `defaultTierThemes` on first run; persisted as JSON thereafter.
    static var tierThemes: [TierTheme] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "tierThemes"),
                  let decoded = try? JSONDecoder().decode([TierTheme].self, from: data),
                  !decoded.isEmpty
            else { return defaultTierThemes }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "tierThemes")
        }
    }

    static var activeTierTheme: TierTheme {
        tierThemes.first { $0.id == activeTierThemeId } ?? tierThemes[0]
    }

    /// Medals ladder calibrated to observed daily spend (median ~$29, p90
    /// ~$55, max ~$98), extended with an "Overboard" step past Diamond; and a
    /// bird-growth ladder that reaches Roasted chicken above $100/day.
    static let defaultTierThemes: [TierTheme] = [
        TierTheme(id: "medals", name: "Medals", steps: [
            TierStep(name: "Warmup", icon: "", unlockAtDollars: 0),
            TierStep(name: "Bronze", icon: "🥉", unlockAtDollars: 10),
            TierStep(name: "Silver", icon: "🥈", unlockAtDollars: 25),
            TierStep(name: "Gold", icon: "🥇", unlockAtDollars: 50),
            TierStep(name: "Diamond", icon: "💎", unlockAtDollars: 80),
            TierStep(name: "Overboard", icon: "💩", unlockAtDollars: 100),
        ]),
        TierTheme(id: "birds", name: "Bird Growth", steps: [
            TierStep(name: "Nest", icon: "🪹", unlockAtDollars: 0),
            TierStep(name: "Egg", icon: "🥚", unlockAtDollars: 10),
            TierStep(name: "Chicken", icon: "🐔", unlockAtDollars: 40),
            TierStep(name: "Roasted chicken", icon: "🍗", unlockAtDollars: 100),
        ]),
    ]
}
