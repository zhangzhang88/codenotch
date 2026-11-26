import Foundation

/// Tokens spent against a bare `GEMINI_API_KEY`, added up from the logs the
/// tools that made the calls keep for themselves.
///
/// There is no endpoint behind this one. Google meters an API key on the
/// billing account and publishes nothing an app could read, so the only record
/// of a call is the one Gemini CLI, OpenCode or Hermes wrote after making it.
/// Each of those keeps its own count, each counts a slightly different thing,
/// and the three readers next door reconcile that; what is left here is adding
/// them up and saying which log each row came from, because a single
/// unattributable total is impossible to check against anything.
///
/// Nothing is cached: every fetch re-reads three local paths, which is
/// prompt-free — no keychain is involved, and no network is either.
actor GeminiAPIProvider: UsageProvider {
    /// Spelled once, because the pure snapshot builder below is static and
    /// cannot reach the instance. An id that drifted from the one the archive
    /// and the disconnected set are keyed by would lose the user's state.
    fileprivate static let providerID = "gemini-api"
    fileprivate static let providerName = "Gemini API"

    nonisolated let id = GeminiAPIProvider.providerID
    nonisolated let displayName = GeminiAPIProvider.providerName
    // The Gemini sparkle, not Antigravity's arch: this row is the model API,
    // and the arch is the editor's own mark, which the neighbouring provider
    // already wears.
    nonisolated let glyph = ProviderGlyph.geminiSpark

    nonisolated private let cliRoot: URL
    nonisolated private let openCodeDatabase: URL
    nonisolated private let hermesDatabase: URL
    nonisolated private let settingsFile: URL
    /// Optional Google AI Studio Billing web session. When signed in, billing
    /// balances (prepaid credit balance, eligible GCP credits, monthly spend
    /// limit) take the headline and local tool logs follow underneath.
    nonisolated(unsafe) private let billingWeb: WebSessionProvider?
    /// Read fresh on every fetch rather than captured once: the user can change
    /// it in Settings while the app runs, and the ring has to follow.
    private let budget: @Sendable () -> Int?

    /// The tools the last fetch actually found, for the settings row.
    /// `nonisolated(unsafe)` because `account()` reads it off the actor, the
    /// same bargain `GLMProvider.lastKnownPlan` makes; the worst a race can do
    /// is name yesterday's tools for one row-draw.
    nonisolated(unsafe) private var lastTools: [String] = []

    init(
        cliRoot: URL = GeminiCLIUsage.sessionsRoot,
        openCodeDatabase: URL = OpenCodeGeminiUsage.database,
        hermesDatabase: URL = HermesGeminiUsage.database,
        settingsFile: URL = GeminiAPICredentials.settingsFile,
        billingWeb: WebSessionProvider? = nil,
        budget: @escaping @Sendable () -> Int?
    ) {
        self.cliRoot = cliRoot
        self.openCodeDatabase = openCodeDatabase
        self.hermesDatabase = hermesDatabase
        self.settingsFile = settingsFile
        self.billingWeb = billingWeb
        self.budget = budget
    }

    nonisolated var signInRoute: SignInRoute {
        if billingWeb != nil {
            return .modal(name: "Google AI Studio")
        }
        return .guidance(L10n.t("There is nothing to sign in to: the count is added up from what Gemini CLI, OpenCode and Hermes recorded about their own calls. Your API key is never read."))
    }

    nonisolated func presentSignIn() {
        guard let billingWeb else { return }
        Task { @MainActor in billingWeb.presentSignIn() }
    }

    nonisolated func presentAccountSwitch() {
        guard let billingWeb else { return }
        let signedIn = billingWeb.account() != nil
        Task { @MainActor in
            if signedIn {
                billingWeb.presentAccountSwitch()
            } else {
                billingWeb.presentSignIn()
            }
        }
    }

    func signOut() async {
        await billingWeb?.signOut()
    }

    nonisolated func account() -> ProviderAccount? {
        if billingWeb?.account() != nil {
            let sourceNames = ["Google AI Studio"] + lastTools
            return ProviderAccount(
                label: nil,
                plan: nil,
                source: sourceNames.joined(separator: ", "),
                manageURL: AIStudioBilling.manageURL
            )
        }
        return GeminiAPICredentials.account(
            tools: lastTools,
            authType: GeminiAPICredentials.authType(at: settingsFile)
        )
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let now = Date()
        if let billingWeb, billingWeb.account() != nil {
            let billingSnapshot = try await billingWeb.fetchSnapshot()
            return Self.snapshot(
                billingWindows: billingSnapshot.windows,
                billingHeadlineID: billingSnapshot.headlineID,
                sources: [],
                now: now
            )
        }

        let sources = sources(now: now)
        lastTools = sources.map(\.name)

        // Not an error and not a missing sign-in when local-only: none of the
        // three tools has ever run here, so there is genuinely nothing metered.
        // When AI Studio Billing is available, prompt to sign in instead.
        guard !sources.isEmpty else {
            if billingWeb != nil {
                throw UsageProviderError.needsAuth
            }
            throw UsageProviderError.nothingMetered(
                L10n.t("No Gemini CLI, OpenCode or Hermes sessions found"))
        }
        return Self.snapshot(sources: sources, budget: budget(), now: now)
    }

    /// One entry per tool that has state on disk, in a fixed order so the
    /// tooltip's rows do not shuffle between refreshes. A reader answering
    /// `nil` means its tool was never installed, which is not the same as a
    /// zero and must not be shown as one.
    private func sources(now: Date) -> [GeminiTokenSource] {
        let readings: [(id: String, name: String, usage: GeminiTokenUsage?)] = [
            ("cli", "Gemini CLI", GeminiCLIUsage.read(root: cliRoot, now: now)),
            ("opencode", "OpenCode", OpenCodeGeminiUsage.read(database: openCodeDatabase, now: now)),
            ("hermes", "Hermes", HermesGeminiUsage.read(database: hermesDatabase, now: now))
        ]
        return readings.compactMap { reading in
            reading.usage.map {
                GeminiTokenSource(id: reading.id, name: reading.name, usage: $0)
            }
        }
    }

    /// The whole visible surface, kept pure so it can be tested without a disk.
    static func snapshot(
        sources: [GeminiTokenSource],
        budget: Int?,
        now: Date = Date()
    ) -> ProviderSnapshot {
        // A budget of zero or less is the same statement as no budget, and
        // dividing by it would draw an infinite ring.
        let budget = budget.flatMap { $0 > 0 ? $0 : nil }
        let total = sources.reduce(GeminiTokenUsage.zero) { $0.adding($1.usage) }
        let calendar = GeminiTokenUsage.calendar
        let month = calendar.dateInterval(of: .month, for: now)

        var windows = [
            LimitWindow(
                id: "month",
                label: budget.map { "Tokens this month · budget \(LimitWindow.compact($0))" }
                    ?? "Tokens this month · billed per token, no limit",
                usedFraction: budget.map { Double(total.tokensThisMonth) / Double($0) },
                used: total.tokensThisMonth,
                resetsAt: month?.end,
                duration: month?.duration
            ),
            LimitWindow(
                id: "today",
                label: "Tokens today",
                used: total.tokensToday,
                resetsAt: calendar.dateInterval(of: .day, for: now)?.end
            )
        ]
        // The rows that make the headline checkable: which tool spent what.
        windows += sources.map {
            LimitWindow(id: $0.id, label: "\($0.name) · this month", used: $0.usage.tokensThisMonth)
        }

        return ProviderSnapshot(
            id: providerID,
            displayName: providerName,
            glyph: .geminiSpark,
            // `.manual` once there is a budget, because the ceiling the ring
            // fills against is the user's own guess, not a limit Google set.
            // Either way the number is ours, so the tooltip keeps its `~`.
            fidelity: budget == nil ? .derived : .manual,
            status: .ok,
            windows: windows,
            headlineID: "month",
            block: nil
        )
    }

    /// Combines Google AI Studio billing windows (headline + credit breakdown +
    /// monthly spend limit) with optional local tool token counts underneath.
    static func snapshot(
        billingWindows: [LimitWindow],
        billingHeadlineID: String? = "ai-studio-total",
        sources: [GeminiTokenSource],
        now: Date = Date()
    ) -> ProviderSnapshot {
        var windows = billingWindows
        if !sources.isEmpty {
            let total = sources.reduce(GeminiTokenUsage.zero) { $0.adding($1.usage) }
            let calendar = GeminiTokenUsage.calendar
            if total.tokensThisMonth > 0 {
                let month = calendar.dateInterval(of: .month, for: now)
                windows.append(LimitWindow(
                    id: "month",
                    label: L10n.t("Tokens this month"),
                    used: total.tokensThisMonth,
                    resetsAt: month?.end,
                    duration: month?.duration
                ))
            }
            if total.tokensToday > 0 {
                windows.append(LimitWindow(
                    id: "today",
                    label: L10n.t("Tokens today"),
                    used: total.tokensToday,
                    resetsAt: calendar.dateInterval(of: .day, for: now)?.end
                ))
            }
        }
        let resolvedHeadline = billingHeadlineID.flatMap { id in
            windows.contains { $0.id == id } ? id : nil
        } ?? windows.first?.id
        return ProviderSnapshot(
            id: providerID,
            displayName: providerName,
            glyph: .geminiSpark,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: resolvedHeadline,
            block: nil
        )
    }
}
