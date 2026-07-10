import AppKit
import SwiftUI

// MARK: - Observable model bridging the scanner to SwiftUI

final class UsageModel: ObservableObject {
    @Published var snapshot = Snapshot()
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}
}

// MARK: - Popover content

struct UsageView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        let snapshot = model.snapshot
        let theme = Config.activeTierTheme
        let tier = Tiers.current(forSpend: snapshot.todayCost, in: theme)
        let next = Tiers.next(forSpend: snapshot.todayCost, in: theme)
        let last7 = snapshot.last14Days.suffix(7).map(\.cost).reduce(0, +)
        let peakHour = snapshot.hourlyToday.indices.max(by: { snapshot.hourlyToday[$0] < snapshot.hourlyToday[$1] })
        let topModelCost = snapshot.costByModelThisMonth.map(\.cost).max() ?? 0

        VStack(alignment: .leading, spacing: 14) {
            // TODAY
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "TODAY")
                    Spacer()
                    Text(tier.icon.isEmpty ? tier.name : "\(tier.name) \(tier.icon)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Spend").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMoney(snapshot.todayCost))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                TierProgress(fraction: tierFraction(tier: tier, next: next, spend: snapshot.todayCost),
                             caption: tierCaption(next: next, spend: snapshot.todayCost),
                             atTop: next == nil)
                StatRow(label: "Tokens",
                        value: "\(formatTokens(snapshot.inputTokensToday)) in · \(formatTokens(snapshot.outputTokensToday)) out")
                if snapshot.averagePerActiveDay > 0 {
                    let above = snapshot.todayCost >= snapshot.averagePerActiveDay
                    StatRow(label: "Pace",
                            value: "\(above ? "↑" : "↓") \(formatMoney(snapshot.averagePerActiveDay))/day avg")
                }
            }

            Hairline()

            // THIS MONTH
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "THIS MONTH")
                StatRow(label: "Month-to-date", value: formatMoney(snapshot.monthCost), emphasis: true)
                StatRow(label: "Projected total", value: formatMoney(snapshot.projectedMonthCost), emphasis: true)
                StatRow(label: "Busiest day",
                        value: "\(snapshot.busiestDayLabel) · \(formatMoney(snapshot.busiestDayCost))",
                        accent: true)
                let budgetFraction = snapshot.monthCost / max(snapshot.monthlyBudgetDollars, 0.01)
                VStack(alignment: .leading, spacing: 5) {
                    StatRow(label: "Budget", value: "\(formatMoney(snapshot.monthCost)) of \(formatMoney(snapshot.monthlyBudgetDollars))")
                    ProgressBar(fraction: budgetFraction,
                                tint: budgetFraction >= 1 ? .red : (budgetFraction >= 0.9 ? .orange : Theme.accent))
                }
            }

            // BY MODEL
            if !snapshot.costByModelThisMonth.isEmpty {
                Hairline()
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "BY MODEL")
                    ForEach(Array(snapshot.costByModelThisMonth.enumerated()), id: \.offset) { index, model in
                        ModelBar(name: model.name, cost: model.cost, maxCost: topModelCost, isTop: index == 0)
                    }
                }
            }

            Hairline()

            // TODAY BY HOUR
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader(title: "TODAY BY HOUR")
                    Spacer()
                    if let peakHour, snapshot.hourlyToday[peakHour] > 0 {
                        Text(String(format: "peak %02d:00 · %@", peakHour, formatMoney(snapshot.hourlyToday[peakHour])))
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                BarChart(values: snapshot.hourlyToday)
            }

            Hairline()

            // LAST 14 DAYS
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader(title: "LAST 14 DAYS")
                    Spacer()
                    Text("7d · \(formatMoney(last7))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                BarChart(values: snapshot.last14Days.map(\.cost))
            }

            Hairline()

            // FOOTER
            HStack(spacing: 12) {
                Button("Refresh") { model.onRefresh() }
                    .buttonStyle(.borderless)
                Button("Settings…") { model.onOpenSettings() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func tierFraction(tier: TierStep, next: TierStep?, spend: Double) -> Double {
        guard let next else { return 1 }
        let span = next.unlockAtDollars - tier.unlockAtDollars
        guard span > 0 else { return 0 }
        return min(max((spend - tier.unlockAtDollars) / span, 0), 1)
    }

    private func tierCaption(next: TierStep?, spend: Double) -> String {
        guard let next else { return "Top tier reached 🎉" }
        return "Next: \(next.name) \(next.icon) in \(formatMoney(next.unlockAtDollars - spend))"
    }
}
