import XCTest
@testable import Codenotch

final class AIStudioBillingTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_795_680_000) // 2026-11-26

    func testMoneyParsesCommonGoogleFormats() {
        let jpyInt = AIStudioMoney.parse("JP¥800")
        XCTAssertEqual(jpyInt?.currencyCode, "JPY")
        XCTAssertEqual(jpyInt?.displayPrefix, "JP¥")
        XCTAssertEqual(jpyInt?.amount, 800)
        XCTAssertEqual(jpyInt?.formattedExact, "JP¥800")
        XCTAssertEqual(jpyInt?.formattedCompact, "800")

        let jpyGcp = AIStudioMoney.parse("JP¥1528.97 符合条件的 GCP 赠金")
        XCTAssertEqual(jpyGcp?.currencyCode, "JPY")
        XCTAssertEqual(jpyGcp?.amount ?? 0, 1528.97, accuracy: 0.001)
        XCTAssertEqual(jpyGcp?.formattedExact, "JP¥1,528.97")
        XCTAssertEqual(jpyGcp?.formattedCompact, "1,529")

        let jpyGrouped = AIStudioMoney.parse("JP¥1,650")
        XCTAssertEqual(jpyGrouped?.currencyCode, "JPY")
        XCTAssertEqual(jpyGrouped?.amount, 1650)

        let usd = AIStudioMoney.parse("US$12.50 eligible GCP credits")
        XCTAssertEqual(usd?.currencyCode, "USD")
        XCTAssertEqual(usd?.displayPrefix, "US$")
        XCTAssertEqual(usd?.amount ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(usd?.formattedCompact, "12.50")

        let eur = AIStudioMoney.parse("12,50 €")
        XCTAssertEqual(eur?.currencyCode, "EUR")
        XCTAssertEqual(eur?.amount ?? 0, 12.5, accuracy: 0.001)

        let compactK = AIStudioMoney.parse("¥1.53K eligible GCP credits")
        XCTAssertEqual(compactK?.currencyCode, "JPY")
        XCTAssertEqual(compactK?.displayPrefix, "JP¥")
        XCTAssertEqual(compactK?.amount ?? 0, 1530, accuracy: 0.001)
        XCTAssertEqual(compactK?.formattedExact, "JP¥1,530")

        let yenPlain = AIStudioMoney.parse("¥54")
        XCTAssertEqual(yenPlain?.displayPrefix, "JP¥")
        XCTAssertEqual(yenPlain?.formattedExact, "JP¥54")

        let yen800 = AIStudioMoney.parse("¥800")
        XCTAssertEqual(yen800?.displayPrefix, "JP¥")
        XCTAssertEqual(yen800?.formattedExact, "JP¥800")

        let compactZh = AIStudioMoney.parse("JP¥1.53千 符合条件的 GCP 赠金")
        XCTAssertEqual(compactZh?.currencyCode, "JPY")
        XCTAssertEqual(compactZh?.amount ?? 0, 1530, accuracy: 0.001)

        let compactWan = AIStudioMoney.parse("¥1.2万")
        XCTAssertEqual(compactWan?.displayPrefix, "JP¥")
        XCTAssertEqual(compactWan?.amount ?? 0, 12_000, accuracy: 0.001)

        let compactM = AIStudioMoney.parse("$2.5M")
        XCTAssertEqual(compactM?.currencyCode, "USD")
        XCTAssertEqual(compactM?.amount ?? 0, 2_500_000, accuracy: 0.001)
    }

    func testTopUpDateAndExpiryCalculation() throws {
        let cal = GeminiTokenUsage.calendar
        let nov26 = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 17))!
        let expectedNov22 = cal.date(from: DateComponents(year: 2026, month: 11, day: 22))!

        let cjk = try XCTUnwrap(AIStudioBilling.parseTopUpDate("11月22日", now: nov26))
        XCTAssertEqual(cjk, expectedNov22)
        XCTAssertEqual(AIStudioBilling.daysUntilPrepayExpiry(topUpDate: cjk, now: nov26), 361)

        let enShort = try XCTUnwrap(AIStudioBilling.parseTopUpDate("Nov 22", now: nov26))
        XCTAssertEqual(enShort, expectedNov22)
        XCTAssertEqual(AIStudioBilling.daysUntilPrepayExpiry(topUpDate: enShort, now: nov26), 361)

        XCTAssertEqual(AIStudioBilling.parseTopUpDate("Nov 22, 2026", now: nov26), expectedNov22)
        XCTAssertEqual(AIStudioBilling.parseTopUpDate("2026-11-22", now: nov26), expectedNov22)

        // Year rollover: "Dec 20" viewed on Jan 5, 2026 refers to Dec 20, 2025 (349 days until Dec 20, 2026).
        let jan5 = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
        let dec20 = try XCTUnwrap(AIStudioBilling.parseTopUpDate("Dec 20", now: jan5))
        XCTAssertEqual(dec20, cal.date(from: DateComponents(year: 2025, month: 12, day: 20))!)
        XCTAssertEqual(AIStudioBilling.daysUntilPrepayExpiry(topUpDate: dec20, now: jan5), 349)
    }

    func testWindowsBuildTotalPrepayGCPCreditsAndMonthlyLimit() throws {
        let payload = #"""
        {
          "prepayBalance": "¥800",
          "prepayTopUpDate": "11月22日",
          "gcpCredits": "¥1528.97 符合条件的 GCP 赠金",
          "monthlySpendUsed": "¥54",
          "monthlySpendLimit": "¥1,650"
        }
        """#

        let windows = try AIStudioBilling.windows(from: payload, now: fixedDate)
        XCTAssertEqual(
            windows.map(\.id),
            ["ai-studio-total", "ai-studio-prepay", "ai-studio-gcp-credits", "ai-studio-monthly-limit"]
        )

        let total = try XCTUnwrap(windows.first)
        XCTAssertEqual(total.usedText, "2,329")
        XCTAssertEqual(total.detail, "JP¥2,328.97")
        XCTAssertTrue(total.prefersUsedText)
        XCTAssertEqual(total.bandOverride, .ample)
        XCTAssertNil(total.usedFraction)

        XCTAssertTrue(windows[1].label.contains("361"))
        XCTAssertEqual(windows[1].detail, "JP¥800")
        XCTAssertEqual(windows[2].detail, "JP¥1,528.97")

        let limit = windows[3]
        XCTAssertEqual(try XCTUnwrap(limit.usedFraction), 54.0 / 1650.0, accuracy: 0.0001)
        XCTAssertEqual(limit.detail, "JP¥54 / JP¥1,650")
        let expectedMonth = try XCTUnwrap(AIStudioBilling.pacificMonthInterval(for: fixedDate))
        XCTAssertEqual(limit.resetsAt, expectedMonth.end)
        XCTAssertEqual(limit.duration, expectedMonth.duration)
    }

    func testWindowsHandleMissingOptionalFieldsGracefully() throws {
        let onlyGCP = #"{"prepayBalance":null,"gcpCredits":"$10.00 eligible GCP credits","monthlySpendUsed":null,"monthlySpendLimit":null}"#
        let windows = try AIStudioBilling.windows(from: onlyGCP, now: fixedDate)
        XCTAssertEqual(windows.map(\.id), ["ai-studio-total", "ai-studio-gcp-credits"])
        XCTAssertEqual(windows.first?.usedText, "10")
        XCTAssertEqual(windows.first?.detail, "$10")

        let depleted = #"{"prepayBalance":"JP¥0","gcpCredits":null,"monthlySpendUsed":null,"monthlySpendLimit":null}"#
        let depletedWindows = try AIStudioBilling.windows(from: depleted, now: fixedDate)
        XCTAssertEqual(depletedWindows.first?.bandOverride, .exhausted)
        XCTAssertEqual(depletedWindows.first?.usedFraction, 1)
    }

    func testEmptyPayloadThrowsNothingMetered() {
        let empty = #"{"prepayBalance":null,"gcpCredits":null,"monthlySpendUsed":null,"monthlySpendLimit":null}"#
        XCTAssertThrowsError(try AIStudioBilling.windows(from: empty, now: fixedDate))
    }

    @MainActor
    func testValidBillingProbeCompletesSignIn() {
        let site = AIStudioBilling.site
        XCTAssertTrue(site.confirmsSignInFromUsage)
        XCTAssertTrue(site.reloadsOnFetch)
        XCTAssertNotNil(site.childFrameScript)

        let valid = #"{"status":200,"body":"{\"prepayBalance\":\"JP¥800\",\"gcpCredits\":\"JP¥1528.97\"}"}"#
        XCTAssertTrue(WebSessionProvider.hasValidSignInUsage(valid, site: site))

        let pending = #"{"status":202,"body":""}"#
        XCTAssertFalse(WebSessionProvider.hasValidSignInUsage(pending, site: site))

        let unauth = #"{"status":401,"body":""}"#
        XCTAssertFalse(WebSessionProvider.hasValidSignInUsage(unauth, site: site))
    }

    func testGeminiAPIProviderCombinesBillingAndLocalTokenUsage() throws {
        let billingWindows = try AIStudioBilling.windows(
            from: #"{"prepayBalance":"JP¥800","gcpCredits":"JP¥1528.97","monthlySpendUsed":"JP¥54","monthlySpendLimit":"JP¥1,650"}"#,
            now: fixedDate
        )
        let localSources = [
            GeminiTokenSource(id: "hermes", name: "Hermes", usage: GeminiTokenUsage(
                tokensThisMonth: 120_000, tokensToday: 15_000, callsThisMonth: 42
            ))
        ]
        let snapshot = GeminiAPIProvider.snapshot(
            billingWindows: billingWindows,
            sources: localSources,
            now: fixedDate
        )

        XCTAssertEqual(snapshot.id, "gemini-api")
        XCTAssertEqual(snapshot.headlineID, "ai-studio-total")
        XCTAssertEqual(snapshot.headlineText, "2,329")
        XCTAssertEqual(snapshot.fidelity, .official)
        XCTAssertEqual(
            snapshot.windows.map(\.id),
            ["ai-studio-total", "ai-studio-prepay", "ai-studio-gcp-credits", "ai-studio-monthly-limit", "month", "today"]
        )

        let zeroLocal = [
            GeminiTokenSource(id: "hermes", name: "Hermes", usage: .zero)
        ]
        let cleanSnapshot = GeminiAPIProvider.snapshot(
            billingWindows: billingWindows,
            sources: zeroLocal,
            now: fixedDate
        )
        XCTAssertEqual(
            cleanSnapshot.windows.map(\.id),
            ["ai-studio-total", "ai-studio-prepay", "ai-studio-gcp-credits", "ai-studio-monthly-limit"]
        )
    }
}
