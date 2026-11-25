import XCTest
@testable import Codenotch

final class GeminiAppUsageTests: XCTestCase {
    @MainActor
    func testValidUsageCompletesSignInWithoutALoggedOutSample() {
        let site = GeminiAppUsage.site
        XCTAssertTrue(site.confirmsSignInFromUsage)
        XCTAssertEqual(site.authProbeScript, site.script)
        let usage = #"{"status":200,"body":"[{\"type\":\"GXU_WEEKLY\",\"used\":0.09}]"}"#
        var gate = WebSessionAuthenticationGate(
            baselineFingerprint: nil,
            requiresNewFingerprint: false,
            acceptsExistingSession: site.confirmsSignInFromUsage
        )
        XCTAssertTrue(gate.observe(authenticated: WebSessionProvider.hasValidSignInUsage(usage, site: site),
                                   fingerprint: nil))
    }

    @MainActor
    func testSignInRequiresAUsableGeminiQuotaResponse() {
        let site = GeminiAppUsage.site
        XCTAssertFalse(WebSessionProvider.hasValidSignInUsage(#"{"status":200,"body":"[]"}"#, site: site))
        XCTAssertFalse(WebSessionProvider.hasValidSignInUsage(#"{"status":401,"body":""}"#, site: site))
        XCTAssertFalse(WebSessionProvider.hasValidSignInUsage(true, site: site))
    }

    func testExistingSessionDoesNotCompleteAnAccountSwitch() {
        var gate = WebSessionAuthenticationGate(baselineFingerprint: "old", acceptsExistingSession: true)
        XCTAssertFalse(gate.observe(authenticated: true, fingerprint: "old"))
    }

    func testIndependentQuotaWindows() throws {
        let windows = try GeminiAppUsage.windows(#"""
        [{"type":"GXU_WEEKLY","used":0.08,"reset":"2026-11-28T13:18:00Z"},
         {"type":"GXU_FIVE_HOURLY","used":0.01}]
        """#)
        XCTAssertEqual(windows.map(\.id), ["gemini-app-5h", "gemini-app-weekly"])
        XCTAssertEqual(windows.map(\.usedFraction), [0.01, 0.08])
        XCTAssertNotNil(windows.last?.resetsAt)
    }

    func testDoesNotSubstituteAntigravityQuota() {
        XCTAssertThrowsError(try GeminiAppUsage.windows(#"[{"type":"gemini-weekly","used":0.86}]"#))
        XCTAssertThrowsError(try GeminiAppUsage.windows(#"[{"type":"GXU_WEEKLY","used":-1}]"#))
    }
}
