import Foundation

// MARK: - App coordinator (owns the scanner and the poll loop)

/// The app's business layer: owns the usage scanner and the poll timer, and
/// publishes each refresh as a `Snapshot` via `onSnapshot`. AppKit-free.
final class AppCoordinator {
    private let scanner: UsageScanning
    private let updateChecker: UpdateChecking
    private let workQueue = DispatchQueue(label: "claude-code-usage.scan", qos: .utility)
    private var timer: Timer?

    /// At most one GitHub update check per this interval, across launches.
    private let updateCheckIntervalSeconds: TimeInterval = 6 * 60 * 60
    private let lastUpdateCheckKey = "lastUpdateCheckAt"

    /// Last published snapshot, so a settings change can trigger a re-render
    /// once the next scan lands, without the view tracking it separately.
    private(set) var latest = Snapshot()

    /// Called on the main thread after each scan with the new snapshot.
    var onSnapshot: ((Snapshot) -> Void)?

    /// Called on the main thread with the newer version string when a newer
    /// release than the running app is available.
    var onUpdateAvailable: ((String) -> Void)?

    init(scanner: UsageScanning = UsageScanner(currentPricingCatalog: { BundledPricingFeed.catalog }),
         updateChecker: UpdateChecking = GitHubReleaseChecker()) {
        self.scanner = scanner
        self.updateChecker = updateChecker
    }

    /// Does a first scan and starts the repeating timer.
    func start(refreshIntervalSeconds: TimeInterval = 60) {
        refresh()
        checkForUpdateIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Polls GitHub for a newer release, but no more often than
    /// `updateCheckIntervalSeconds` to stay well under the unauthenticated API
    /// rate limit. The timestamp is written before the request so a failed
    /// check still backs off rather than retrying on every launch.
    private func checkForUpdateIfDue() {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastUpdateCheckKey)
        guard now - last >= updateCheckIntervalSeconds else { return }
        UserDefaults.standard.set(now, forKey: lastUpdateCheckKey)
        updateChecker.checkForUpdate { [weak self] version in
            guard let version else { return }
            DispatchQueue.main.async { self?.onUpdateAvailable?(version) }
        }
    }

    func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.scanner.scan()
            DispatchQueue.main.async {
                self.latest = snapshot
                self.onSnapshot?(snapshot)
            }
        }
    }
}
