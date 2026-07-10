import Foundation

// MARK: - Formatting helpers

func formatMoney(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.0fK", Double(count) / 1_000) }
    return "\(count)"
}

private let dayLabelFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    return f
}()

/// Short weekday + date label for chart tooltips, e.g. "Thu Jul 2".
func formatDayLabel(_ date: Date) -> String {
    dayLabelFormatter.string(from: date)
}
