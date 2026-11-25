import XCTest
@testable import Codenotch

final class GeminiAppUsageTests: XCTestCase {
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
