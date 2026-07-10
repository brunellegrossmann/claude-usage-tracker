import Foundation

// MARK: - Spend tiers (a themed ladder of steps unlocked by today's spend)

struct TierStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String
    var unlockAtDollars: Double
}

struct TierTheme: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var steps: [TierStep]
}
