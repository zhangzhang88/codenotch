import Foundation

/// Gemini chat usage comes from the Gemini usage page, independently of Antigravity.
enum GeminiAppUsage {
    @MainActor static var site: WebSessionProvider.Site {
        WebSessionProvider.Site(
            id: "gemini-app",
            displayName: "Gemini App",
            glyph: .geminiSpark,
            origin: URL(string: "https://gemini.google.com")!,
            script: requestScript + "return JSON.stringify(await readUsage());",
            authProbeScript: requestScript + "return (await readUsage()).status === 200;",
            logsResponseBody: false,
            pollsDuringSignIn: true,
            initialPath: "usage",
            headlineID: "gemini-app-5h",
            weeklyID: "gemini-app-weekly",
            parse: windows
        )
    }

    // Use the same quota query as the Gemini usage page. The WebView owns the
    // session, and only quota fields cross from JavaScript to Swift.
    private static let requestScript = #"""
    async function readUsage() {
        const failure = status => ({ status, body: "" });
        if (location.origin !== "https://gemini.google.com") return failure(401);
        const url = new URL("/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery", location.origin);
        url.searchParams.set("query_signature", "2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g=");
        url.searchParams.set("variables", JSON.stringify({
            g1Request: { entrypoints: ["GEMINI_USAGE_SETTINGS_UPGRADE_BANNER"] },
            workspaceRequest: { recommendationsForSurfaceRequests: [] }
        }));
        const slot = location.pathname.match(/^\/u\/([0-9]{1,3})\//)?.[1]
            ?? new URLSearchParams(location.search).get("authuser");
        if (slot !== null) {
            if (!/^[0-9]{1,3}$/.test(slot)) return failure(422);
            url.searchParams.set("authuser", slot);
        }
        const response = await fetch(url, {
            credentials: "same-origin", redirect: "error",
            headers: { Accept: "application/json" }, signal: AbortSignal.timeout(15000)
        });
        if (!response.ok) return failure(response.status);
        const raw = (await response.text()).trim();
        if (raw.startsWith("<")) return failure(401);
        const results = JSON.parse(raw.replace(/^\)\]\}'\s*/, ""));
        if (!Array.isArray(results)) return failure(422);
        const data = results.map(result => result?.data).find(item => item && Object.hasOwn(item, "viewer"));
        if (data?.viewer === null) return failure(401);
        const pools = data?.viewer?.rpcs?.getUsageInfo?.pools;
        if (!Array.isArray(pools)) return failure(422);
        return { status: 200, body: JSON.stringify(pools
            .filter(pool => ["GXU_FIVE_HOURLY", "GXU_WEEKLY"].includes(pool?.poolType))
            .map(pool => ({
                type: pool.poolType, used: pool.percentageUsed,
                reset: pool.gxu?.windowRefreshesAt
            }))) };
    }
    """# + "\n"

    private struct Pool: Decodable {
        let type: String
        let used: Double?
        let reset: String?
    }

    static func windows(_ body: String) throws -> [LimitWindow] {
        let pools = try JSONDecoder().decode([Pool].self, from: Data(body.utf8))
        let roles: [(type: String, id: String, label: String, duration: TimeInterval)] = [
            ("GXU_FIVE_HOURLY", "gemini-app-5h", L10n.t("5-hour Limit"), 5 * 3600),
            ("GXU_WEEKLY", "gemini-app-weekly", L10n.t("Weekly Limit"), 7 * 86400)
        ]
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let windows: [LimitWindow] = try roles.compactMap { role in
            let matches = pools.filter { $0.type == role.type }
            guard matches.count <= 1 else { throw UsageProviderError.badResponse(status: 200) }
            guard let pool = matches.first, let used = pool.used, used.isFinite, used >= 0 else {
                return nil
            }
            let reset = pool.reset.flatMap { fractional.date(from: $0) ?? formatter.date(from: $0) }
            return LimitWindow(id: role.id, label: role.label, usedFraction: min(used, 1),
                               resetsAt: reset, duration: role.duration)
        }
        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered(L10n.t("This account reports no Gemini App quota"))
        }
        return windows
    }
}
