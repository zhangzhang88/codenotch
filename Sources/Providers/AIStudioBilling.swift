import Foundation

/// A parsed monetary figure reported by Google AI Studio's Billing or Spend page.
///
/// Preserves the site's own currency prefix (such as `JP¥` or `US$`) alongside
/// a normalized currency code so sums and formatted rows match what the user
/// sees on `aistudio.google.com/billing` and `/spend`.
struct AIStudioMoney: Equatable, Sendable {
    let currencyCode: String
    let displayPrefix: String
    let amount: Double

    /// Zero-decimal currencies that should round to whole units in the compact
    /// notch headline while still allowing fractional display in the card when
    /// Google reports decimals (such as `JP¥1,528.97`).
    private static let wholeHeadlineCurrencies: Set<String> = ["JPY", "KRW", "VND", "IDR"]

    var formattedExact: String {
        let hasFraction = abs(amount - amount.rounded()) >= 0.005
        return Self.format(amount, prefix: displayPrefix, fractionDigits: hasFraction ? 2 : 0)
    }

    /// Compact numeric reading (no currency prefix) for the tight notch pill
    /// and menu bar so multi-digit balances are not clipped under the icon.
    var formattedCompact: String {
        if Self.wholeHeadlineCurrencies.contains(currencyCode) || abs(amount) >= 1_000 {
            return Self.format(amount.rounded(), prefix: "", fractionDigits: 0)
        }
        let hasFraction = abs(amount - amount.rounded()) >= 0.005
        return Self.format(amount, prefix: "", fractionDigits: hasFraction ? 2 : 0)
    }

    private static func format(_ value: Double, prefix: String, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(fractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
        return "\(prefix)\(number)"
    }

    private struct CurrencySpec {
        let token: String
        let code: String
        let prefix: String
    }

    /// Ordered longest-token-first so `JP¥` matches before `¥` and `US$` before `$`.
    private static let prefixSpecs: [CurrencySpec] = [
        .init(token: "JP¥", code: "JPY", prefix: "JP¥"),
        .init(token: "JP￥", code: "JPY", prefix: "JP¥"),
        .init(token: "CN¥", code: "CNY", prefix: "CN¥"),
        .init(token: "CN￥", code: "CNY", prefix: "CN¥"),
        .init(token: "US$", code: "USD", prefix: "US$"),
        .init(token: "NT$", code: "TWD", prefix: "NT$"),
        .init(token: "HK$", code: "HKD", prefix: "HK$"),
        .init(token: "CA$", code: "CAD", prefix: "CA$"),
        .init(token: "AU$", code: "AUD", prefix: "AU$"),
        .init(token: "NZ$", code: "NZD", prefix: "NZ$"),
        .init(token: "SG$", code: "SGD", prefix: "SG$"),
        .init(token: "MX$", code: "MXN", prefix: "MX$"),
        .init(token: "R$", code: "BRL", prefix: "R$"),
        .init(token: "A$", code: "AUD", prefix: "A$"),
        .init(token: "S$", code: "SGD", prefix: "S$"),
        .init(token: "C$", code: "CAD", prefix: "C$"),
        .init(token: "USD", code: "USD", prefix: "$"),
        .init(token: "JPY", code: "JPY", prefix: "JP¥"),
        .init(token: "CNY", code: "CNY", prefix: "CN¥"),
        .init(token: "RMB", code: "CNY", prefix: "CN¥"),
        .init(token: "EUR", code: "EUR", prefix: "€"),
        .init(token: "GBP", code: "GBP", prefix: "£"),
        .init(token: "KRW", code: "KRW", prefix: "₩"),
        .init(token: "INR", code: "INR", prefix: "₹"),
        .init(token: "TWD", code: "TWD", prefix: "NT$"),
        .init(token: "HKD", code: "HKD", prefix: "HK$"),
        .init(token: "CAD", code: "CAD", prefix: "CA$"),
        .init(token: "AUD", code: "AUD", prefix: "A$"),
        .init(token: "SGD", code: "SGD", prefix: "S$"),
        .init(token: "CHF", code: "CHF", prefix: "CHF "),
        .init(token: "$", code: "USD", prefix: "$"),
        .init(token: "€", code: "EUR", prefix: "€"),
        .init(token: "£", code: "GBP", prefix: "£"),
        .init(token: "¥", code: "JPY", prefix: "JP¥"),
        .init(token: "￥", code: "JPY", prefix: "JP¥"),
        .init(token: "₩", code: "KRW", prefix: "₩"),
        .init(token: "₹", code: "INR", prefix: "₹")
    ]

    private static let suffixSpecs: [CurrencySpec] = [
        .init(token: "USD", code: "USD", prefix: "$"),
        .init(token: "JPY", code: "JPY", prefix: "JP¥"),
        .init(token: "CNY", code: "CNY", prefix: "CN¥"),
        .init(token: "EUR", code: "EUR", prefix: "€"),
        .init(token: "GBP", code: "GBP", prefix: "£"),
        .init(token: "CHF", code: "CHF", prefix: "CHF "),
        .init(token: "円", code: "JPY", prefix: "JP¥"),
        .init(token: "€", code: "EUR", prefix: "€"),
        .init(token: "$", code: "USD", prefix: "$"),
        .init(token: "£", code: "GBP", prefix: "£"),
        .init(token: "¥", code: "JPY", prefix: "JP¥"),
        .init(token: "￥", code: "JPY", prefix: "JP¥")
    ]

    private static let compactMultipliers: [(suffix: String, multiplier: Double)] = [
        ("十亿", 1_000_000_000),
        ("十億", 1_000_000_000),
        ("百万", 1_000_000),
        ("百萬", 1_000_000),
        ("亿", 100_000_000),
        ("億", 100_000_000),
        ("万", 10_000),
        ("萬", 10_000),
        ("千", 1_000),
        ("B", 1_000_000_000),
        ("M", 1_000_000),
        ("K", 1_000)
    ]

    /// Extracts the first currency amount from a billing label or standalone
    /// figure such as `"JP¥800"`, `"JP¥1528.97 符合条件的 GCP 赠金"`, `"¥1.53K"`,
    /// `"¥1.53千"`, or `"12,50 €"`.
    static func parse(_ raw: String) -> AIStudioMoney? {
        let normalized = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let unitGroup = "(?:十亿|十億|百万|百萬|亿|億|万|萬|千|[KMB](?![A-Za-z]))?"

        // Prefix form: `<currency>[space]<number>[space][compact unit]`
        for spec in prefixSpecs {
            let escaped = NSRegularExpression.escapedPattern(for: spec.token)
            let pattern = "\(escaped)\\s*([0-9][0-9,.]*)\\s*(\(unitGroup))"
            if let (numberText, unitText) = firstNumberAndUnit(pattern: pattern, in: normalized),
               let base = parseNumber(numberText) {
                let amount = base * multiplier(for: unitText)
                return AIStudioMoney(currencyCode: spec.code, displayPrefix: spec.prefix, amount: amount)
            }
        }

        // Suffix form: `<number>[space][compact unit][space]<currency>`
        for spec in suffixSpecs {
            let escaped = NSRegularExpression.escapedPattern(for: spec.token)
            let pattern = "([0-9][0-9,.]*)\\s*(\(unitGroup))\\s*\(escaped)"
            if let (numberText, unitText) = firstNumberAndUnit(pattern: pattern, in: normalized),
               let base = parseNumber(numberText) {
                let amount = base * multiplier(for: unitText)
                return AIStudioMoney(currencyCode: spec.code, displayPrefix: spec.prefix, amount: amount)
            }
        }

        return nil
    }

    private static func multiplier(for unit: String) -> Double {
        guard !unit.isEmpty else { return 1 }
        let upper = unit.uppercased()
        for entry in compactMultipliers where entry.suffix == unit || entry.suffix == upper {
            return entry.multiplier
        }
        return 1
    }

    private static func firstNumberAndUnit(pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let numberRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let unitText: String
        if let unitRange = Range(match.range(at: 2), in: text) {
            unitText = String(text[unitRange])
        } else {
            unitText = ""
        }
        return (String(text[numberRange]), unitText)
    }

    private static func parseNumber(_ text: String) -> Double? {
        // Trim trailing punctuation (e.g. a period ending a sentence).
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        guard !trimmed.isEmpty else { return nil }

        let cleaned: String
        if trimmed.contains(".") && trimmed.contains(",") {
            // Whichever separator appears last is the decimal mark.
            let lastDot = trimmed.lastIndex(of: ".")!
            let lastComma = trimmed.lastIndex(of: ",")!
            if lastComma > lastDot {
                cleaned = trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = trimmed.replacingOccurrences(of: ",", with: "")
            }
        } else if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count == 1 || parts[1].count == 2 {
                // European decimal comma (e.g. "12,50").
                cleaned = "\(parts[0]).\(parts[1])"
            } else {
                // Thousands grouping separator (e.g. "1,650" or "1,528,000").
                cleaned = trimmed.replacingOccurrences(of: ",", with: "")
            }
        } else {
            cleaned = trimmed
        }

        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Reads Google AI Studio Billing (`/billing`) and Spend (`/spend`) figures
/// inside Codenotch's own `WKWebView` session:
/// - Prepaid credit balance (`赠金余额`, inside the embedded `payments.google.com` frame)
/// - Eligible GCP credits (`符合条件的 GCP 赠金`, on `/billing`)
/// - Monthly spend limit (`每月支出上限`, on `/spend`)
enum AIStudioBilling {
    static let sessionKey = "gemini-api.aistudio.signedIn"
    static let manageURL = URL(string: "https://aistudio.google.com/billing")!

    struct Payload: Decodable, Equatable {
        let prepayBalance: String?
        let prepayTopUpDate: String?
        let gcpCredits: String?
        let monthlySpendUsed: String?
        let monthlySpendLimit: String?
    }

    struct Reading: Equatable {
        let prepayBalance: AIStudioMoney?
        let prepayTopUpDate: Date?
        let gcpCredits: AIStudioMoney?
        let monthlySpendUsed: AIStudioMoney?
        let monthlySpendLimit: AIStudioMoney?

        init(prepayBalance: AIStudioMoney?,
             prepayTopUpDate: Date? = nil,
             gcpCredits: AIStudioMoney?,
             monthlySpendUsed: AIStudioMoney?,
             monthlySpendLimit: AIStudioMoney?) {
            self.prepayBalance = prepayBalance
            self.prepayTopUpDate = prepayTopUpDate
            self.gcpCredits = gcpCredits
            self.monthlySpendUsed = monthlySpendUsed
            self.monthlySpendLimit = monthlySpendLimit
        }

        /// Combined spendable credits (`prepayBalance + gcpCredits`) when both
        /// share the same currency, or whichever credit figure is present.
        var totalAvailable: AIStudioMoney? {
            switch (prepayBalance, gcpCredits) {
            case let (prepay?, gcp?) where prepay.currencyCode == gcp.currencyCode:
                return AIStudioMoney(
                    currencyCode: prepay.currencyCode,
                    displayPrefix: prepay.displayPrefix,
                    amount: prepay.amount + gcp.amount
                )
            case let (prepay?, _):
                return prepay
            case let (nil, gcp?):
                return gcp
            case (nil, nil):
                return nil
            }
        }
    }

    @MainActor static var site: WebSessionProvider.Site {
        WebSessionProvider.Site(
            id: "gemini-api",
            displayName: "Google AI Studio",
            glyph: .geminiSpark,
            origin: URL(string: "https://aistudio.google.com")!,
            script: fetchScript,
            fidelity: .official,
            authProbeScript: authProbeScript,
            sessionKey: sessionKey,
            logsResponseBody: false,
            associatedHosts: ["payments.google.com"],
            pollsDuringSignIn: true,
            confirmsSignInFromUsage: true,
            reloadsSessionOnAuthFailure: true,
            managePath: "billing",
            initialPath: "billing",
            childFrameScript: paymentsFrameScript,
            reloadsOnFetch: true,
            maxSignInProbeAttempts: 24,
            headlineID: "ai-studio-total",
            parse: { body in try windows(from: body) }
        )
    }

    static func parseReading(from body: String, now: Date = Date()) throws -> Reading {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(body.utf8))
        return Reading(
            prepayBalance: payload.prepayBalance.flatMap(AIStudioMoney.parse),
            prepayTopUpDate: payload.prepayTopUpDate.flatMap { Self.parseTopUpDate($0, now: now) },
            gcpCredits: payload.gcpCredits.flatMap(AIStudioMoney.parse),
            monthlySpendUsed: payload.monthlySpendUsed.flatMap(AIStudioMoney.parse),
            monthlySpendLimit: payload.monthlySpendLimit.flatMap(AIStudioMoney.parse)
        )
    }

    static func windows(from body: String, now: Date = Date()) throws -> [LimitWindow] {
        let reading = try parseReading(from: body, now: now)
        let result = windows(from: reading, now: now)
        guard !result.isEmpty else {
            throw UsageProviderError.nothingMetered(L10n.t("No Google AI Studio billing balance found"))
        }
        return result
    }

    static func windows(from reading: Reading, now: Date = Date()) -> [LimitWindow] {
        var windows: [LimitWindow] = []

        if let total = reading.totalAvailable {
            let exhausted = total.amount <= 0
            windows.append(LimitWindow(
                id: "ai-studio-total",
                label: L10n.t("Available credits"),
                usedFraction: exhausted ? 1 : nil,
                used: 0,
                usedText: total.formattedCompact,
                detail: total.formattedExact,
                bandOverride: exhausted ? .exhausted : .ample,
                prefersUsedText: true
            ))
        }

        if let prepay = reading.prepayBalance {
            let prepayLabel: String
            if let topUpDate = reading.prepayTopUpDate {
                let days = Self.daysUntilPrepayExpiry(topUpDate: topUpDate, now: now)
                let expiryText = String(format: L10n.t("expires in %d days"), days)
                prepayLabel = "\(L10n.t("Prepaid balance")) · \(expiryText)"
            } else {
                prepayLabel = L10n.t("Prepaid balance")
            }
            windows.append(LimitWindow(
                id: "ai-studio-prepay",
                label: prepayLabel,
                detail: prepay.formattedExact
            ))
        }

        if let gcp = reading.gcpCredits {
            windows.append(LimitWindow(
                id: "ai-studio-gcp-credits",
                label: L10n.t("Eligible GCP credits"),
                detail: gcp.formattedExact
            ))
        }

        if let used = reading.monthlySpendUsed,
           let limit = reading.monthlySpendLimit,
           limit.amount > 0 {
            let fraction = max(used.amount / limit.amount, 0)
            let month = Self.pacificMonthInterval(for: now)
            windows.append(LimitWindow(
                id: "ai-studio-monthly-limit",
                label: L10n.t("Monthly spend limit"),
                usedFraction: fraction,
                detail: "\(used.formattedExact) / \(limit.formattedExact)",
                resetsAt: month?.end,
                duration: month?.duration
            ))
        }

        return windows
    }

    /// Google AI Studio monthly spend limits reset on the 1st of each calendar
    /// month at 00:00 Pacific Time (`America/Los_Angeles`).
    static func pacificMonthInterval(for date: Date) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3600)!
        return calendar.dateInterval(of: .month, for: date)
    }

    /// Parses the prepaid credit top-up date reported by the `payments.google.com`
    /// widget (e.g. `"11月22日"`, `"Nov 22"`, `"Nov 22, 2026"`, `"2026-11-22"`).
    /// When the year is omitted, picks the most recent occurrence not after `now`.
    static func parseTopUpDate(_ raw: String,
                             now: Date = Date(),
                             calendar: Calendar = GeminiTokenUsage.calendar) -> Date? {
        let normalized = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        func makeDate(year: Int, month: Int, day: Int) -> Date? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else { return nil }
            let check = calendar.dateComponents([.year, .month, .day], from: date)
            guard check.year == year, check.month == month, check.day == day else { return nil }
            return date
        }

        func resolve(year explicitYear: Int?, month: Int, day: Int) -> Date? {
            if let explicitYear {
                return makeDate(year: explicitYear, month: month, day: day)
            }
            let currentYear = calendar.component(.year, from: now)
            let todayStart = calendar.startOfDay(for: now)
            if let candidate = makeDate(year: currentYear, month: month, day: day) {
                if calendar.startOfDay(for: candidate) > todayStart {
                    return makeDate(year: currentYear - 1, month: month, day: day)
                }
                return candidate
            }
            // Handles Feb 29 when `currentYear` is not a leap year.
            return makeDate(year: currentYear - 1, month: month, day: day)
        }

        func matchGroups(pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
            else { return nil }
            return (1..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: normalized) else { return "" }
                return String(normalized[range])
            }
        }

        // 1. CJK: "2026年11月22日" or "11月22日"
        if let groups = matchGroups(pattern: #"^(?:(\d{4})\s*[年/\-.]\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*日$"#),
           let month = Int(groups[1]), let day = Int(groups[2]) {
            return resolve(year: Int(groups[0]), month: month, day: day)
        }

        // 2. ISO / numeric: "2026-11-22" or "2026/11/22"
        if let groups = matchGroups(pattern: #"^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$"#),
           let year = Int(groups[0]), let month = Int(groups[1]), let day = Int(groups[2]) {
            return makeDate(year: year, month: month, day: day)
        }

        // 3. US numeric: "11/22/2026"
        if let groups = matchGroups(pattern: #"^(\d{1,2})/(\d{1,2})/(\d{4})$"#),
           let month = Int(groups[0]), let day = Int(groups[1]), let year = Int(groups[2]) {
            return makeDate(year: year, month: month, day: day)
        }

        // 4. English month names: "Nov 22", "Nov 22, 2026", "22 Nov", "22 Nov 2026"
        let monthMap: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]

        if let groups = matchGroups(pattern: #"^([A-Za-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,\s*(\d{4}))?$"#),
           let month = monthMap[groups[0].lowercased()],
           let day = Int(groups[1]) {
            return resolve(year: Int(groups[2]), month: month, day: day)
        }

        if let groups = matchGroups(pattern: #"^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\.?(?:\s*,?\s*(\d{4}))?$"#),
           let day = Int(groups[0]),
           let month = monthMap[groups[1].lowercased()] {
            return resolve(year: Int(groups[2]), month: month, day: day)
        }

        return nil
    }

    /// Prepaid AI Studio credits expire 1 year after the top-up date.
    static func daysUntilPrepayExpiry(topUpDate: Date,
                                      now: Date = Date(),
                                      calendar: Calendar = GeminiTokenUsage.calendar) -> Int {
        let expiry = calendar.date(byAdding: .year, value: 1, to: topUpDate) ?? topUpDate
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expiry)
        ).day ?? 0
        return max(0, days)
    }

    /// Runs inside every frame (`forMainFrameOnly: false`), activates only inside
    /// `payments.google.com/payments/.../embedded_landing_page`, and reports ONLY
    /// the rendered prepaid credit balance string back to Swift.
    static let paymentsFrameScript = #"""
    (() => {
        if (location.hostname !== "payments.google.com") return;
        if (!location.pathname.includes("embedded_landing_page")) return;

        const moneyRegex = /^(?:(?:JP|CN)[¥￥]|(?:US|NT|HK|CA|AU|NZ|SG|MX|R|A|S|C)\$|USD|JPY|CNY|RMB|EUR|GBP|KRW|INR|TWD|HKD|CAD|AUD|SGD|CHF|[$€£¥￥₩₹])\s*[0-9][0-9,.]*$|^[0-9][0-9,.]*\s*(?:USD|JPY|CNY|EUR|GBP|CHF|円|[$€£¥￥])$/i;
        const labelRegex = /^(credit balance|prepaid balance|remaining balance|balance|赠金余额|抵用金余额|抵用金餘額|クレジット残高|크레딧 잔액|guthaben|solde(?: de crédit)?|saldo(?: de crédito)?)$/i;

        const isVisible = el => {
            if (!el || el.nodeType !== 1) return false;
            const style = getComputedStyle(el);
            return style.display !== "none" && style.visibility !== "hidden" && parseFloat(style.opacity || "1") > 0;
        };

        const cleanText = el => (el?.textContent || "").replace(/[\u00A0\u202F]/g, " ").trim();

        const findMoneyInSubtree = root => {
            if (!root) return null;
            let best = null;
            let bestSize = -1;
            const nodes = root.querySelectorAll ? root.querySelectorAll("*") : [];
            for (const el of nodes) {
                if (el.children.length > 0 || !isVisible(el)) continue;
                const text = cleanText(el);
                if (!moneyRegex.test(text)) continue;
                const size = parseFloat(getComputedStyle(el).fontSize || "0") || 0;
                if (size > bestSize) {
                    best = text;
                    bestSize = size;
                }
            }
            return best;
        };

        const extractBalance = () => {
            const all = document.querySelectorAll("*");
            for (const el of all) {
                if (el.children.length > 0 || !isVisible(el)) continue;
                const text = cleanText(el);
                if (!labelRegex.test(text)) continue;
                if (el.nextElementSibling) {
                    const direct = cleanText(el.nextElementSibling);
                    if (moneyRegex.test(direct)) return direct;
                    const nested = findMoneyInSubtree(el.nextElementSibling);
                    if (nested) return nested;
                }
                for (const container of [el.parentElement, el.parentElement?.parentElement]) {
                    const found = findMoneyInSubtree(container);
                    if (found) return found;
                }
            }
            // Language-independent fallback: the largest standalone currency figure in the widget.
            let hero = null;
            let heroSize = 19;
            for (const el of all) {
                if (el.children.length > 0 || !isVisible(el)) continue;
                const text = cleanText(el);
                if (!moneyRegex.test(text)) continue;
                const size = parseFloat(getComputedStyle(el).fontSize || "0") || 0;
                if (size > heroSize) {
                    hero = text;
                    heroSize = size;
                }
            }
            return hero;
        };

        const extractTopUpDate = () => {
            const cjkRegex = /(?:\d{4}\s*[年/\-.]\s*)?\d{1,2}\s*月\s*\d{1,2}\s*日/;
            const enMonthFirstRegex = /(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:\s*,\s*\d{4})?/i;
            const enDayFirstRegex = /\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?(?:\s+\d{4})?/i;
            const isoRegex = /\d{4}[/-]\d{1,2}[/-]\d{1,2}/;
            const usNumericRegex = /\d{1,2}\/\d{1,2}\/\d{4}/;
            const keywordRegex = /refill|top(?:ped)?\s*up|added|charged|充入|充值|补充|補充|チャージ|충전/i;

            const matchDate = text => {
                for (const re of [cjkRegex, enMonthFirstRegex, enDayFirstRegex, isoRegex, usNumericRegex]) {
                    const m = text.match(re);
                    if (m && m[0].length <= 32) return m[0].trim();
                }
                return null;
            };

            let fallback = null;
            const all = document.querySelectorAll("*");
            for (const el of all) {
                if (!isVisible(el)) continue;
                const text = cleanText(el);
                if (!text || text.length > 120) continue;
                const dateStr = matchDate(text);
                if (!dateStr) continue;
                if (keywordRegex.test(text)) return dateStr;
                if (!fallback && el.children.length === 0) fallback = dateStr;
            }
            return fallback;
        };

        let lastPosted = null;
        const report = () => {
            const value = extractBalance();
            if (!value) return;
            const topUpDate = extractTopUpDate();
            const payload = { prepayBalance: value };
            if (topUpDate) payload.prepayTopUpDate = topUpDate;
            const serialized = JSON.stringify(payload);
            if (serialized === lastPosted) return;
            lastPosted = serialized;
            try {
                window.webkit?.messageHandlers?.codenotchFrameData?.postMessage(payload);
            } catch (_) {}
        };

        report();
        let timer = null;
        const observer = new MutationObserver(() => {
            if (timer) return;
            timer = setTimeout(() => { timer = null; report(); }, 150);
        });
        if (document.body) {
            observer.observe(document.body, { childList: true, subtree: true, characterData: true });
        }
        let polls = 0;
        const interval = setInterval(() => {
            report();
            polls += 1;
            if (polls >= 40) clearInterval(interval);
        }, 500);
    })();
    """#

    /// Non-navigating probe used while the sign-in sheet is open on `/billing`.
    /// Waits briefly for the embedded `payments.google.com` frame to mount and
    /// report its credit balance so the first reading already includes both figures.
    static let authProbeScript = #"""
    const failure = status => JSON.stringify({ status, body: "" });
    if (location.origin !== "https://aistudio.google.com") return failure(401);
    if (location.pathname.startsWith("/welcome")) return failure(401);
    if (!location.pathname.startsWith("/billing")) return failure(202);
    const billingRoot = document.querySelector("ms-billing");
    if (!billingRoot) return failure(202);

    const gcpButton = document.querySelector("ms-billing-credits button.view-credits-button");
    const gcpCredits = gcpButton ? gcpButton.textContent.replace(/[\u00A0\u202F]/g, " ").trim() : null;
    const prepayBalance = window.__codenotchFrameData?.prepayBalance || null;
    const prepayTopUpDate = window.__codenotchFrameData?.prepayTopUpDate || null;
    const hasPaymentsSection = !!document.querySelector("ms-payments, #payments-widget-containerIframe");

    if (!window.__codenotchBillingSeenAt) window.__codenotchBillingSeenAt = Date.now();
    const waitedMs = Date.now() - window.__codenotchBillingSeenAt;

    // Wait for the embedded payments iframe to mount and report prepaid credits.
    if (!prepayBalance && (waitedMs < 3500 || (hasPaymentsSection && waitedMs < 9000))) {
        return failure(202);
    }
    if (!prepayBalance && !gcpCredits) {
        return failure(202);
    }
    return JSON.stringify({
        status: 200,
        body: JSON.stringify({ prepayBalance, prepayTopUpDate, gcpCredits, monthlySpendUsed: null, monthlySpendLimit: null })
    });
    """#

    /// Full refresh script: reads prepaid credit balance + exact eligible GCP
    /// credits from `/billing`, then switches via the SPA sidebar to `/spend`
    /// to read the monthly spend limit (`used / limit`), and returns to `/billing`.
    static let fetchScript = #"""
    const failure = status => JSON.stringify({ status, body: "" });
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    const clean = el => el ? el.textContent.replace(/[\u00A0\u202F]/g, " ").trim() : null;

    if (location.origin !== "https://aistudio.google.com") return failure(401);
    if (location.pathname.startsWith("/welcome")) return failure(401);

    const clickNav = prefix => {
        const links = Array.from(document.querySelectorAll('a[href]'));
        const target = links.find(a => {
            try {
                const u = new URL(a.href, location.origin);
                return u.origin === location.origin && u.pathname.startsWith(prefix);
            } catch (_) { return false; }
        });
        if (target) { target.click(); return true; }
        return false;
    };

    if (!location.pathname.startsWith("/billing")) {
        clickNav("/billing");
    }

    let prepayBalance = null;
    let prepayTopUpDate = null;
    let gcpCredits = null;
    let billingSettledAt = null;
    let paymentsFrameSeenAt = null;
    const billingDeadline = Date.now() + 15000;

    while (Date.now() < billingDeadline) {
        if (location.pathname.startsWith("/welcome")) return failure(401);
        const billingRoot = document.querySelector("ms-billing");
        const hasAccount = !!document.querySelector("ms-billing .has-selected-billing-account, ms-billing-account-selector");
        const gcpEl = document.querySelector("ms-billing-credits button.view-credits-button");
        if (gcpEl) {
            const text = clean(gcpEl);
            if (text) gcpCredits = text;
        }
        const frameBalance = window.__codenotchFrameData?.prepayBalance || null;
        if (frameBalance) prepayBalance = frameBalance;
        const frameTopUpDate = window.__codenotchFrameData?.prepayTopUpDate || null;
        if (frameTopUpDate) prepayTopUpDate = frameTopUpDate;

        if (billingRoot && hasAccount) {
            if (!billingSettledAt) billingSettledAt = Date.now();
            const hasPaymentsFrame = !!document.querySelector("#payments-widget-containerIframe");
            const hasPaymentsHost = hasPaymentsFrame || !!document.querySelector("ms-payments");
            if (hasPaymentsFrame && !paymentsFrameSeenAt) paymentsFrameSeenAt = Date.now();

            const elapsedSinceSettled = Date.now() - billingSettledAt;
            const elapsedSinceFrame = paymentsFrameSeenAt ? (Date.now() - paymentsFrameSeenAt) : 0;

            // Both balances ready (or payments arrived and GCP credits had time to render).
            if (prepayBalance && (gcpCredits || elapsedSinceSettled >= 2000)) break;
            // Give the payments iframe time to mount after Angular renders the account bar,
            // and once mounted give payments.google.com up to 9s to finish rendering.
            if (!hasPaymentsHost && elapsedSinceSettled >= 4500) break;
            if (hasPaymentsHost && !hasPaymentsFrame && elapsedSinceSettled >= 6000) break;
            if (hasPaymentsFrame && elapsedSinceFrame >= 9000) break;
        }
        await sleep(250);
    }

    // The header credits link can render compact notation (e.g. "¥1.53K" or "¥1.53千").
    // Opening the credits drawer reveals the exact un-abbreviated balance in `.hero-balance-val`.
    const gcpButton = document.querySelector("ms-billing-credits button.view-credits-button");
    if (gcpButton && gcpCredits && /(?:[0-9]\s*(?:十亿|十億|百万|百萬|亿|億|万|萬|千|[KMB](?![A-Za-z])))/i.test(gcpCredits)) {
        gcpButton.click();
        const drawerDeadline = Date.now() + 2500;
        while (Date.now() < drawerDeadline) {
            const exact = clean(document.querySelector(".credits-hero .hero-balance-val"));
            if (exact) {
                gcpCredits = exact;
                break;
            }
            await sleep(150);
        }
        const closeBtn = document.querySelector(".ms-sliding-right-panel-dialog button[aria-label*='Close'], .ms-sliding-right-panel-dialog button[aria-label*='关闭'], .cdk-overlay-backdrop");
        if (closeBtn) closeBtn.click();
        await sleep(150);
    }

    // Navigate via Angular SPA router to /spend for the monthly spend limit.
    let monthlySpendUsed = null;
    let monthlySpendLimit = null;

    let clickedSpend = clickNav("/spend");
    if (!clickedSpend) {
        const navDeadline = Date.now() + 3000;
        while (Date.now() < navDeadline && !clickedSpend) {
            await sleep(200);
            clickedSpend = clickNav("/spend");
        }
    }

    if (clickedSpend) {
        const spendDeadline = Date.now() + 9000;
        let dashboardSeenAt = null;
        while (Date.now() < spendDeadline) {
            if (location.pathname.startsWith("/spend")) {
                const usedEl = document.querySelector("ms-project-usage-limit .usage-limit-container .usage");
                const limitEl = document.querySelector("ms-project-usage-limit .usage-limit-container .limit");
                const usedText = clean(usedEl);
                const limitText = clean(limitEl);
                if (usedText && limitText) {
                    monthlySpendUsed = usedText;
                    monthlySpendLimit = limitText;
                    break;
                }
                const dashboard = document.querySelector("ms-billing-dashboard");
                const limitWidget = document.querySelector("ms-project-usage-limit");
                const isSpinning = !!limitWidget?.querySelector("mat-spinner, mat-progress-spinner, .loading, .spinner");
                if (dashboard && !isSpinning) {
                    if (!dashboardSeenAt) dashboardSeenAt = Date.now();
                    if (Date.now() - dashboardSeenAt >= 3500) break;
                }
            }
            await sleep(250);
        }
        clickNav("/billing");
    }

    if (!prepayBalance && !gcpCredits && !(monthlySpendUsed && monthlySpendLimit)) {
        if (!document.querySelector("ms-billing, ms-billing-dashboard")) return failure(401);
        return JSON.stringify({
            status: 200,
            body: JSON.stringify({ prepayBalance: null, prepayTopUpDate: null, gcpCredits: null, monthlySpendUsed: null, monthlySpendLimit: null })
        });
    }

    return JSON.stringify({
        status: 200,
        body: JSON.stringify({ prepayBalance, prepayTopUpDate, gcpCredits, monthlySpendUsed, monthlySpendLimit })
    });
    """#
}
