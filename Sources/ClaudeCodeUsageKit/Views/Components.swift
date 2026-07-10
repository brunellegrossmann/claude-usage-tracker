import SwiftUI

// MARK: - Reusable SwiftUI pieces

/// A small uppercase section header.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.4)
    }
}

/// A hairline divider: 0.5pt at low opacity, closer to native macOS than a solid rule.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
    }
}

/// A label/value row. `emphasis` bumps size + weight for headline numbers;
/// `accent` tints the value for the one-or-two highlighted stats.
struct StatRow: View {
    let label: String
    let value: String
    var emphasis: Bool = false
    var accent: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: emphasis ? 15 : 12,
                              weight: emphasis ? .bold : .semibold,
                              design: .monospaced))
                .foregroundStyle(accent ? Theme.accent : Color.primary)
        }
    }
}

/// Capsule progress track: a filled portion (`tint`) over a faint full-width base.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// Progress toward the next tier, with a caption naming it and its cost away.
struct TierProgress: View {
    let fraction: Double
    let caption: String
    let atTop: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressBar(fraction: atTop ? 1 : fraction, tint: Theme.accent)
            Text(caption)
                .font(.caption)
                .foregroundStyle(atTop ? Theme.accent : .secondary)
        }
    }
}

/// Vertical bar chart with rounded caps, gradient fill, and the peak bar in accent.
struct BarChart: View {
    let values: [Double]
    var height: CGFloat = 40

    var body: some View {
        let maxValue = values.max() ?? 0
        let peak = values.indices.max(by: { values[$0] < values[$1] })
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                let ratio = maxValue > 0 ? values[index] / maxValue : 0
                Capsule()
                    .fill(index == peak && maxValue > 0 ? Theme.accentBar : Theme.neutralBar)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, CGFloat(ratio) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// One row of the "by model" mini bar chart: name, proportional capsule, cost.
struct ModelBar: View {
    let name: String
    let cost: Double
    let maxCost: Double
    let isTop: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(isTop ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.22)))
                    .frame(width: max(3, geo.size.width * (maxCost > 0 ? cost / maxCost : 0)))
                    .frame(maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 6)
            Text(formatMoney(cost))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
