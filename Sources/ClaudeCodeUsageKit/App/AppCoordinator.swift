import Foundation

// MARK: - App coordinator (owns the scanner and the poll loop)

/// The app's business layer: owns the usage scanner and the poll timer, and
/// publishes each refresh as a `Snapshot` via `onSnapshot`. AppKit-free.
final class AppCoordinator {
    private let scanner: UsageScanning
    private let workQueue = DispatchQueue(label: "claude-code-usage.scan", qos: .utility)
    private var timer: Timer?

    /// Last published snapshot, so a settings change can trigger a re-render
    /// once the next scan lands, without the view tracking it separately.
    private(set) var latest = Snapshot()

    /// Called on the main thread after each scan with the new snapshot.
    var onSnapshot: ((Snapshot) -> Void)?

    init(scanner: UsageScanning = UsageScanner()) {
        self.scanner = scanner
    }

    /// Does a first scan and starts the repeating timer.
    func start(refreshIntervalSeconds: TimeInterval = 60) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
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
