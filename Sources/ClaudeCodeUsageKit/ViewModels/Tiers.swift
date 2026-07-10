// MARK: - Spend tiers (pure derivation: theme + spend -> current/next step)

/// Everything about which tier step applies, derived from explicit inputs
/// only — no `Config` access here, so it's directly unit-testable. Callers
/// pass in `Config.activeTierTheme`.
enum Tiers {
    /// Highest step whose threshold `spend` has reached, in `theme`.
    static func current(forSpend spend: Double, in theme: TierTheme) -> TierStep {
        let steps = sortedSteps(in: theme)
        return steps.last { spend >= $0.unlockAtDollars } ?? steps[0]
    }

    /// Next step above `spend`, or nil once the top step is reached.
    static func next(forSpend spend: Double, in theme: TierTheme) -> TierStep? {
        sortedSteps(in: theme).first { $0.unlockAtDollars > spend }
    }

    private static func sortedSteps(in theme: TierTheme) -> [TierStep] {
        let steps = theme.steps.sorted { $0.unlockAtDollars < $1.unlockAtDollars }
        return steps.isEmpty ? [TierStep(name: "Warmup", icon: "", unlockAtDollars: 0)] : steps
    }
}
