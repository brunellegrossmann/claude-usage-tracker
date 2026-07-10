import XCTest
@testable import ClaudeCodeUsageKit

final class UpdateCheckerTests: XCTestCase {

    // MARK: - isNewerVersion

    func test_newer_when_latest_has_higher_major_minor_or_patch() {
        XCTAssertTrue(isNewerVersion("2.0.0", than: "1.9.9"))
        XCTAssertTrue(isNewerVersion("1.3.0", than: "1.2.9"))
        XCTAssertTrue(isNewerVersion("1.2.1", than: "1.2.0"))
    }

    func test_not_newer_when_latest_equals_or_is_older() {
        XCTAssertFalse(isNewerVersion("1.2.0", than: "1.2.0"))
        XCTAssertFalse(isNewerVersion("1.2.0", than: "1.3.0"))
        XCTAssertFalse(isNewerVersion("1.0.0", than: "2.0.0"))
    }

    func test_ignores_leading_v_prefix_on_either_side() {
        XCTAssertTrue(isNewerVersion("v1.1.0", than: "v1.0.0"))
        XCTAssertTrue(isNewerVersion("v1.1.0", than: "1.0.0"))
        XCTAssertFalse(isNewerVersion("v1.0.0", than: "1.0.0"))
    }

    func test_compares_numerically_not_lexicographically() {
        XCTAssertTrue(isNewerVersion("1.10.0", than: "1.9.0"))
        XCTAssertFalse(isNewerVersion("1.9.0", than: "1.10.0"))
    }

    func test_treats_missing_trailing_components_as_zero() {
        XCTAssertFalse(isNewerVersion("1.2", than: "1.2.0"))
        XCTAssertTrue(isNewerVersion("1.2.1", than: "1.2"))
    }

    func test_ignores_prerelease_suffix() {
        XCTAssertFalse(isNewerVersion("1.2.0-beta", than: "1.2.0"))
        XCTAssertTrue(isNewerVersion("1.3.0-rc1", than: "1.2.0"))
    }

    func test_unparseable_latest_never_reports_an_update() {
        XCTAssertFalse(isNewerVersion("not-a-version", than: "1.0.0"))
        XCTAssertFalse(isNewerVersion("", than: "1.0.0"))
    }

    // MARK: - GitHubReleaseChecker decision logic (network injected)

    func test_reports_tag_when_fetched_release_is_newer() {
        let checker = GitHubReleaseChecker(currentVersion: "1.0.0", fetchLatestTag: { done in done("v1.1.0") })
        var reported: String?
        checker.checkForUpdate { reported = $0 }
        XCTAssertEqual(reported, "v1.1.0")
    }

    func test_reports_nil_when_fetched_release_is_not_newer() {
        let checker = GitHubReleaseChecker(currentVersion: "1.1.0", fetchLatestTag: { done in done("v1.1.0") })
        var reported: String? = "sentinel"
        checker.checkForUpdate { reported = $0 }
        XCTAssertNil(reported)
    }

    func test_reports_nil_when_fetch_fails() {
        let checker = GitHubReleaseChecker(currentVersion: "1.0.0", fetchLatestTag: { done in done(nil) })
        var reported: String? = "sentinel"
        checker.checkForUpdate { reported = $0 }
        XCTAssertNil(reported)
    }
}
