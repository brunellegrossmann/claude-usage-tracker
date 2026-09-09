import Foundation

// MARK: - Pricing feed (published prices, cached locally)

/// Outcome of one conditional GET of the feed.
enum PricingFeedFetchResult {
    /// The server confirmed the cached copy is current (HTTP 304).
    case notModified
    case updated(Data, etag: String?)
    case failed(String)
}

/// The one network dependency of pricing, injected so the refresh policy is
/// testable without a live request.
protocol PricingFeedTransport {
    func fetch(url: URL, etag: String?, completion: @escaping (PricingFeedFetchResult) -> Void)
}

/// Keeps the app's prices current: serves the best catalog it has, and refreshes
/// from the published feed at most once per `refreshIntervalSeconds`.
///
/// Precedence is strictly bundled < cached < freshly fetched, and a catalog is
/// only adopted after it decodes and validates. A malformed or hostile publish
/// therefore leaves the last good prices in place instead of zeroing costs.
final class PricingFeed {
    /// At most one feed request per 24h, across launches.
    static let refreshIntervalSeconds: TimeInterval = 24 * 60 * 60

    private let transport: PricingFeedTransport
    private let feedURL: URL
    private let cacheFileURL: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let ioQueue = DispatchQueue(label: "claude-code-usage.pricing-feed", qos: .utility)
    private let lock = NSLock()

    private let lastFetchKey = "pricingFeedLastFetchAt"
    private let etagKey = "pricingFeedETag"
    private let cachedAtKey = "pricingFeedCachedAt"

    private var storedCatalog: PricingCatalog

    /// The prices to bill with right now. Safe to read from any thread.
    var catalog: PricingCatalog {
        lock.lock()
        defer { lock.unlock() }
        return storedCatalog
    }

    private var storedFailureReason: String?

    /// Reason the last refresh failed, for display in Settings. Nil when the
    /// last attempt succeeded or none has run yet.
    var lastFailureReason: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedFailureReason
    }

    private func recordFailure(_ reason: String?) {
        lock.lock()
        storedFailureReason = reason
        lock.unlock()
    }

    /// Called on the main thread whenever a newly adopted catalog changes prices.
    var onCatalogChanged: ((PricingCatalog) -> Void)?

    init(
        transport: PricingFeedTransport = URLSessionPricingFeedTransport(),
        feedURL: URL = AppRelease.pricingFeedURL,
        cacheFileURL: URL = PricingFeed.defaultCacheFileURL(),
        defaults: UserDefaults = .standard,
        bundledCatalog: PricingCatalog = BundledPricingFeed.catalog,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.feedURL = feedURL
        self.cacheFileURL = cacheFileURL
        self.defaults = defaults
        self.now = now
        self.storedCatalog = Self.loadCachedCatalog(
            at: cacheFileURL,
            cachedAt: defaults.object(forKey: cachedAtKey) as? Date) ?? bundledCatalog
    }

    /// `~/Library/Application Support/<bundle id>/pricing.json`.
    static func defaultCacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.local.claudecodeusage"
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("pricing.json")
    }

    /// Refreshes only if the interval has elapsed. Called at launch.
    func refreshIfDue() {
        let elapsed = now().timeIntervalSince1970 - defaults.double(forKey: lastFetchKey)
        guard elapsed >= Self.refreshIntervalSeconds else { return }
        refreshNow()
    }

    /// Refreshes regardless of the interval. Backs the manual button in Settings.
    func refreshNow(completion: (() -> Void)? = nil) {
        // Stamped before the request so a failing feed backs off for a day
        // rather than retrying on every scan.
        defaults.set(now().timeIntervalSince1970, forKey: lastFetchKey)
        let etag = defaults.string(forKey: etagKey)
        transport.fetch(url: feedURL, etag: etag) { [weak self] result in
            self?.ioQueue.async {
                self?.handle(result)
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    private func handle(_ result: PricingFeedFetchResult) {
        switch result {
        case .notModified:
            recordFailure(nil)
        case let .failed(reason):
            recordFailure(reason)
        case let .updated(data, etag):
            do {
                let fetchedAt = now()
                let fresh = try PricingCatalogDecoder.decode(data, origin: .feed(fetchedAt: fetchedAt))
                adopt(fresh)
                writeCache(data, fetchedAt: fetchedAt, etag: etag)
                recordFailure(nil)
            } catch {
                // Keep the previous catalog: a bad publish must not change costs.
                recordFailure(String(describing: error))
            }
        }
    }

    private func adopt(_ fresh: PricingCatalog) {
        lock.lock()
        let changed = fresh.models != storedCatalog.models
            || fresh.cacheMultipliers != storedCatalog.cacheMultipliers
        storedCatalog = fresh
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in self?.onCatalogChanged?(fresh) }
    }

    private func writeCache(_ data: Data, fetchedAt: Date, etag: String?) {
        let directory = cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: cacheFileURL, options: .atomic)) != nil else { return }
        defaults.set(fetchedAt, forKey: cachedAtKey)
        if let etag {
            defaults.set(etag, forKey: etagKey)
        } else {
            defaults.removeObject(forKey: etagKey)
        }
    }

    /// The last feed copy written to disk, or nil when absent or no longer valid
    /// for this build (for example a newer schema after a downgrade).
    private static func loadCachedCatalog(at url: URL, cachedAt: Date?) -> PricingCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PricingCatalogDecoder.decode(data, origin: .feed(fetchedAt: cachedAt ?? .distantPast))
    }
}

// MARK: - Real transport

/// Conditional GET over HTTPS. Sends no cookies, no identifiers, and no body:
/// the request carries nothing about the user or their usage.
struct URLSessionPricingFeedTransport: PricingFeedTransport {
    private let timeoutSeconds: TimeInterval = 15

    func fetch(url: URL, etag: String?, completion: @escaping (PricingFeedFetchResult) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeoutSeconds

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failed(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failed("pricing feed returned no HTTP response"))
                return
            }
            switch http.statusCode {
            case 304:
                completion(.notModified)
            case 200:
                guard let data else {
                    completion(.failed("pricing feed returned an empty body"))
                    return
                }
                completion(.updated(data, etag: http.value(forHTTPHeaderField: "ETag")))
            default:
                completion(.failed("pricing feed returned HTTP \(http.statusCode)"))
            }
        }.resume()
    }
}
