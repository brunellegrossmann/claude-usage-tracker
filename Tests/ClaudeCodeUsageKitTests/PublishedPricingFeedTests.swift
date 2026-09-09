import XCTest
@testable import ClaudeCodeUsageKit

/// CI gate on `docs/pricing.json`: it is served to every installed app the
/// moment it is merged, so a typo must fail here rather than in the field.
final class PublishedPricingFeedTests: XCTestCase {

    /// Repo root, derived from this file's own path.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ClaudeCodeUsageKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private var publishedFeedURL: URL {
        repositoryRoot.appendingPathComponent("docs/pricing.json")
    }

    func test_published_feed_is_valid() throws {
        let data = try Data(contentsOf: publishedFeedURL)
        let catalog = try PricingCatalogDecoder.decode(data, origin: .bundled)
        XCTAssertFalse(catalog.models.isEmpty)
        XCTAssertNotNil(parseFeedDate(catalog.updatedAt), "updatedAt must be a date")
    }

    func test_bundled_prices_are_regenerated_from_the_published_feed() throws {
        let published = try String(contentsOf: publishedFeedURL, encoding: .utf8)
        XCTAssertEqual(
            BundledPricingFeed.json.trimmingCharacters(in: .newlines),
            published.trimmingCharacters(in: .newlines),
            "docs/pricing.json changed without regenerating: run Scripts/embed_pricing.sh")
    }

    func test_every_claude_code_model_string_is_priced() {
        let catalog = PricingCatalog.bundledForTests
        // Model strings Claude Code writes into its logs today.
        let modelsInUse = [
            "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001", "claude-fable-5-1",
            "claude-opus-4-8", "claude-opus-4-1-20250805", "claude-sonnet-4-5-20250929",
        ]
        for model in modelsInUse {
            XCTAssertNotNil(catalog.rates(forModel: model, usedOn: Date()), "no rate for \(model)")
        }
    }
}
