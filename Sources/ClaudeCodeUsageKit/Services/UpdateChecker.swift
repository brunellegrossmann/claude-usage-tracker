import Foundation

// MARK: - Update checking (GitHub Releases)

/// Everything tied to where this app is published: the repo it releases from,
/// the running app's version, and the URLs the update check uses.
enum AppRelease {
    /// `owner/repo` this app releases from.
    static let repoSlug = "brunellegrossmann/claude-usage-tracker"

    /// Page a user is sent to when they click "update available".
    static let releasesPageURL = URL(string: "https://github.com/\(repoSlug)/releases/latest")!

    /// Published pricing feed. Served from the repo's GitHub Pages site (the
    /// `docs/` folder on `main`), so a price change ships without an app update.
    static let pricingFeedURL = URL(string: "https://brunellegrossmann.github.io/claude-usage-tracker/pricing.json")!

    /// GitHub REST endpoint returning the latest published release as JSON.
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")!

    /// The running app's version, e.g. "1.2.0". `build.sh` stamps this from the
    /// git tag; dev builds fall back to the value baked into `Info.plist`.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// Is `latest` a strictly newer release than `current`? Tolerates a leading
/// "v" and differing component counts ("1.2" equals "1.2.0"), and ignores any
/// pre-release/build suffix ("1.2.0-beta" compares as "1.2.0"). Returns false
/// when `latest` isn't dotted-numeric, so a malformed API response never nags.
func isNewerVersion(_ latest: String, than current: String) -> Bool {
    guard let latestParts = numericVersionComponents(latest) else { return false }
    let currentParts = numericVersionComponents(current) ?? []
    for index in 0..<max(latestParts.count, currentParts.count) {
        let latestPart = index < latestParts.count ? latestParts[index] : 0
        let currentPart = index < currentParts.count ? currentParts[index] : 0
        if latestPart != currentPart { return latestPart > currentPart }
    }
    return false
}

/// Parses "v1.2.0" / "1.2" / "1.2.0-beta" into `[1, 2, 0]` etc. Returns nil if
/// any component before a "-" suffix isn't a plain integer.
private func numericVersionComponents(_ version: String) -> [Int]? {
    let trimmed = version.trimmingCharacters(in: .whitespaces)
    let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    let core = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
    let parts = core.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return nil }
    var components: [Int] = []
    for part in parts {
        guard let number = Int(part) else { return nil }
        components.append(number)
    }
    return components
}

/// Checks whether a newer release than the running app exists.
protocol UpdateChecking {
    /// Calls `completion` with the newer release's version string, or nil when
    /// the app is up to date or the check failed. May run on any queue.
    func checkForUpdate(completion: @escaping (String?) -> Void)
}

/// Compares the running version against the latest GitHub release tag.
struct GitHubReleaseChecker: UpdateChecking {
    private let currentVersion: String
    /// Fetches the latest release's `tag_name` (nil on failure). Injected so the
    /// decision logic is testable without a live network call.
    private let fetchLatestTag: (@escaping (String?) -> Void) -> Void

    init(
        currentVersion: String = AppRelease.currentVersion,
        fetchLatestTag: @escaping (@escaping (String?) -> Void) -> Void = GitHubReleaseChecker.fetchLatestTagFromGitHub
    ) {
        self.currentVersion = currentVersion
        self.fetchLatestTag = fetchLatestTag
    }

    func checkForUpdate(completion: @escaping (String?) -> Void) {
        fetchLatestTag { tag in
            guard let tag, isNewerVersion(tag, than: currentVersion) else {
                completion(nil)
                return
            }
            completion(tag)
        }
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    /// Default fetcher: GETs the latest-release endpoint and returns its tag.
    static func fetchLatestTagFromGitHub(_ completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: AppRelease.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else {
                completion(nil)
                return
            }
            completion(release.tagName)
        }.resume()
    }
}
