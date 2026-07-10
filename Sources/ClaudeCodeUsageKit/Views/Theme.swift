import SwiftUI

// MARK: - Theme

enum Theme {
    /// The single accent. Claude terracotta-orange (#D97757). Used sparingly:
    /// spend number, tier progress, busiest highlights, peak bars.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)

    /// Vertical accent gradient for the peak bar (top solid → bottom faded).
    static let accentBar = LinearGradient(
        colors: [accent, accent.opacity(0.35)],
        startPoint: .top, endPoint: .bottom
    )

    /// Vertical neutral gradient for non-peak bars.
    static let neutralBar = LinearGradient(
        colors: [Color.primary.opacity(0.32), Color.primary.opacity(0.10)],
        startPoint: .top, endPoint: .bottom
    )
}
