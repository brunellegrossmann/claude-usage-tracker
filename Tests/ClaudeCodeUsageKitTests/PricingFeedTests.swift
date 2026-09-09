import XCTest
@testable import ClaudeCodeUsageKit

/// Fake transport that replays a scripted result and records what it was asked.
private final class StubPricingFeedTransport: PricingFeedTransport {
    var result: PricingFeedFetchResult
    var requestCount = 0
    var lastETagSent: String?

    init(result: PricingFeedFetchResult) {
        self.result = result
    }

    func fetch(url: URL, etag: String?, completion: @escaping (PricingFeedFetchResult) -> Void) {
        requestCount += 1
        lastETagSent = etag
        completion(result)
    }
}

final class PricingFeedTests: XCTestCase {
    private var defaults: UserDefaults!
    private var cacheFileURL: URL!
    private let suiteName = "pricing-feed-tests"

    private let feedJSON = """
    { "schemaVersion": 1, "updatedAt": "2026-09-10", "models": [
        { "id": "demo", "displayName": "Demo", "family": "Demo", "match": ["demo"],
          "periods": [{ "inputPerMillion": 7, "outputPerMillion": 21 }] }
    ]}
    """

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        cacheFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("pricing.json")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: cacheFileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeFeed(
        transport: PricingFeedTransport,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> PricingFeed {
        PricingFeed(
            transport: transport,
            feedURL: URL(string: "https://example.invalid/pricing.json")!,
            cacheFileURL: cacheFileURL,
            defaults: defaults,
            bundledCatalog: .bundledForTests,
            now: now)
    }

    private func refreshAndWait(_ feed: PricingFeed) {
        let done = expectation(description: "refresh finished")
        feed.refreshNow { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    // MARK: Fallback and precedence

    func test_starts_on_the_bundled_prices_when_nothing_is_cached() {
        let feed = makeFeed(transport: StubPricingFeedTransport(result: .notModified))
        XCTAssertEqual(feed.catalog.origin, .bundled)
        XCTAssertEqual(feed.catalog, .bundledForTests)
    }

    func test_adopts_prices_from_a_successful_fetch() {
        let feed = makeFeed(transport: StubPricingFeedTransport(
            result: .updated(Data(feedJSON.utf8), etag: "\"abc\"")))
        refreshAndWait(feed)
        XCTAssertEqual(feed.catalog.rates(forModel: "demo", usedOn: Date())?.inputPerToken,
                       7 / 1_000_000)
        XCTAssertNil(feed.lastFailureReason)
    }

    func test_keeps_the_previous_prices_when_the_feed_is_invalid() {
        let feed = makeFeed(transport: StubPricingFeedTransport(
            result: .updated(Data(#"{"schemaVersion": 1, "updatedAt": "x", "models": []}"#.utf8), etag: nil)))
        refreshAndWait(feed)
        XCTAssertEqual(feed.catalog, .bundledForTests)
        XCTAssertNotNil(feed.lastFailureReason)
    }

    func test_keeps_the_previous_prices_when_the_request_fails() {
        let feed = makeFeed(transport: StubPricingFeedTransport(result: .failed("offline")))
        refreshAndWait(feed)
        XCTAssertEqual(feed.catalog, .bundledForTests)
        XCTAssertEqual(feed.lastFailureReason, "offline")
    }

    func test_an_invalid_feed_is_not_written_to_the_cache() {
        let feed = makeFeed(transport: StubPricingFeedTransport(
            result: .updated(Data("garbage".utf8), etag: nil)))
        refreshAndWait(feed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFileURL.path))
    }

    func test_a_later_launch_reuses_the_cached_prices_without_a_request() {
        let writer = makeFeed(transport: StubPricingFeedTransport(
            result: .updated(Data(feedJSON.utf8), etag: "\"abc\"")))
        refreshAndWait(writer)

        let offline = StubPricingFeedTransport(result: .failed("offline"))
        let reader = makeFeed(transport: offline)
        XCTAssertEqual(reader.catalog.rates(forModel: "demo", usedOn: Date())?.inputPerToken,
                       7 / 1_000_000)
        XCTAssertEqual(offline.requestCount, 0)
    }

    // MARK: Refresh policy

    func test_launch_does_not_refetch_within_the_interval() {
        let transport = StubPricingFeedTransport(result: .updated(Data(feedJSON.utf8), etag: nil))
        let feed = makeFeed(transport: transport)
        refreshAndWait(feed)
        feed.refreshIfDue()
        XCTAssertEqual(transport.requestCount, 1)
    }

    func test_launch_refetches_once_a_day_has_passed() {
        let transport = StubPricingFeedTransport(result: .updated(Data(feedJSON.utf8), etag: nil))
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let feed = makeFeed(transport: transport, now: { clock })
        refreshAndWait(feed)
        clock = clock.addingTimeInterval(PricingFeed.refreshIntervalSeconds + 1)
        feed.refreshIfDue()
        XCTAssertEqual(transport.requestCount, 2)
    }

    func test_a_failed_check_still_backs_off_instead_of_retrying_every_launch() {
        let transport = StubPricingFeedTransport(result: .failed("offline"))
        let feed = makeFeed(transport: transport)
        refreshAndWait(feed)
        feed.refreshIfDue()
        XCTAssertEqual(transport.requestCount, 1)
    }

    func test_the_next_check_revalidates_with_the_stored_etag() {
        let transport = StubPricingFeedTransport(
            result: .updated(Data(feedJSON.utf8), etag: "\"abc\""))
        let feed = makeFeed(transport: transport)
        refreshAndWait(feed)
        transport.result = .notModified
        refreshAndWait(feed)
        XCTAssertEqual(transport.lastETagSent, "\"abc\"")
        XCTAssertNil(feed.lastFailureReason)
    }

    func test_a_price_change_notifies_the_app_so_totals_are_recomputed() {
        let feed = makeFeed(transport: StubPricingFeedTransport(
            result: .updated(Data(feedJSON.utf8), etag: nil)))
        let changed = expectation(description: "catalog changed")
        feed.onCatalogChanged = { _ in changed.fulfill() }
        feed.refreshNow()
        wait(for: [changed], timeout: 2)
    }
}
