import AppKit
import SwiftUI

// MARK: - Observable model bridging the scanner to SwiftUI

final class UsageModel: ObservableObject {
    @Published var snapshot = Snapshot()
    /// Set to the newer release's version string when an update is available;
    /// nil hides the update banner.
    @Published var availableUpdateVersion: String?
    var onOpenSettings: () -> Void = {}
    var onOpenReleasePage: () -> Void = {}
}

// MARK: - Popover content

struct UsageView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        let snapshot = model.snapshot
        let last7 = snapshot.last14Days.suffix(7).map(\.cost).reduce(0, +)
        let peakHour = snapshot.hourlyToday.indices.max(by: { snapshot.hourlyToday[$0] < snapshot.hourlyToday[$1] })
        let topModelCost = snapshot.costByModelThisMonth.map(\.cost).max() ?? 0

        VStack(alignment: .leading, spacing: 14) {
            // UPDATE AVAILABLE
            if let version = model.availableUpdateVersion {
                Button(action: { model.onOpenReleasePage() }) {
                    HStack(spacing: 6) {
                        Text("🔔 Update available: \(version)")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                Hairline()
            }

            // TODAY
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "TODAY")
                StatRow(label: "Spend", value: formatMoney(snapshot.todayCost), emphasis: true, accent: true)
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
                BarChart(values: snapshot.hourlyToday, tooltip: { hour in
                    String(format: "%02d:00 · %@", hour, formatMoney(snapshot.hourlyToday[hour]))
                })
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
                BarChart(values: snapshot.last14Days.map(\.cost), tooltip: { index in
                    let day = snapshot.last14Days[index]
                    return "\(formatDayLabel(day.dayStart)) · \(formatMoney(day.cost))"
                })
            }

            Hairline()

            // FOOTER
            HStack(spacing: 12) {
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
}
