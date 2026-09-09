import XCTest
@testable import ClaudeCodeUsageKit

/// The feed is public config that reaches every installed app without review,
/// so these tests pin what the app refuses to accept.
final class PricingCatalogDecoderTests: XCTestCase {

    private func decode(_ json: String) throws -> PricingCatalog {
        try PricingCatalogDecoder.decode(Data(json.utf8), origin: .bundled)
    }

    private func minimalFeed(models: String) -> String {
        """
        { "schemaVersion": 1, "updatedAt": "2026-09-09", "models": [\(models)] }
        """
    }

    private let validModel = """
    { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"],
      "periods": [{ "inputPerMillion": 3, "outputPerMillion": 15 }] }
    """

    func test_accepts_a_minimal_valid_feed() throws {
        let catalog = try decode(minimalFeed(models: validModel))
        XCTAssertEqual(catalog.models.count, 1)
        XCTAssertEqual(catalog.updatedAt, "2026-09-09")
        XCTAssertEqual(catalog.cacheMultipliers, .anthropicDefaults)
    }

    func test_rejects_a_schema_version_newer_than_this_app() {
        let json = """
        { "schemaVersion": 99, "updatedAt": "2026-09-09", "models": [\(validModel)] }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? PricingCatalogError,
                           .unsupportedSchemaVersion(found: 99, supported: 1))
        }
    }

    func test_rejects_malformed_json() {
        XCTAssertThrowsError(try decode("not json")) { error in
            XCTAssertEqual(error as? PricingCatalogError, .malformedJSON)
        }
    }

    func test_rejects_a_feed_with_no_models() {
        XCTAssertThrowsError(try decode(minimalFeed(models: ""))) { error in
            XCTAssertEqual(error as? PricingCatalogError, .noModels)
        }
    }

    func test_rejects_a_free_or_negative_rate() {
        for rate in ["0", "-3"] {
            let model = """
            { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"],
              "periods": [{ "inputPerMillion": \(rate), "outputPerMillion": 15 }] }
            """
            XCTAssertThrowsError(try decode(minimalFeed(models: model)), "rate \(rate)")
        }
    }

    func test_rejects_an_implausibly_large_rate() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"],
          "periods": [{ "inputPerMillion": 5000, "outputPerMillion": 15 }] }
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_a_model_with_no_match_patterns() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": [],
          "periods": [{ "inputPerMillion": 3, "outputPerMillion": 15 }] }
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_a_model_with_no_price_periods() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [] }
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_overlapping_price_periods() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [
            { "until": "2026-09-01", "inputPerMillion": 2, "outputPerMillion": 10 },
            { "from": "2026-08-01", "inputPerMillion": 3, "outputPerMillion": 15 }
        ]}
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_a_period_that_ends_before_it_starts() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [
            { "from": "2026-09-01", "until": "2026-08-01", "inputPerMillion": 3, "outputPerMillion": 15 }
        ]}
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_an_unparseable_period_date() {
        let model = """
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"], "periods": [
            { "from": "last Tuesday", "inputPerMillion": 3, "outputPerMillion": 15 }
        ]}
        """
        XCTAssertThrowsError(try decode(minimalFeed(models: model)))
    }

    func test_rejects_a_fallback_model_id_that_matches_no_model() {
        let json = """
        { "schemaVersion": 1, "updatedAt": "2026-09-09", "fallbackModelId": "ghost",
          "models": [\(validModel)] }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? PricingCatalogError, .unknownFallbackModelId("ghost"))
        }
    }

    func test_unrecognised_model_is_unpriced_when_the_feed_names_no_fallback() throws {
        let catalog = try decode(minimalFeed(models: validModel))
        XCTAssertNil(catalog.rates(forModel: "claude-something-new", usedOn: Date()))
    }
}
