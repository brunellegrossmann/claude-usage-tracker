import Foundation
@testable import ClaudeCodeUsageKit

extension UsageEntry {
    /// A usage entry with sensible defaults; override only the fields a test
    /// cares about, keeping the many-field memberwise init out of every test.
    static func stub(
        dedupeKey: String = "msg-1|req-1",
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        projectName: String = "demo-project",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0
    ) -> UsageEntry {
        UsageEntry(
            dedupeKey: dedupeKey, timestamp: timestamp, projectName: projectName, model: model,
            inputTokens: inputTokens, outputTokens: outputTokens, cacheReadTokens: cacheReadTokens,
            cacheWrite5mTokens: cacheWrite5mTokens, cacheWrite1hTokens: cacheWrite1hTokens)
    }
}
