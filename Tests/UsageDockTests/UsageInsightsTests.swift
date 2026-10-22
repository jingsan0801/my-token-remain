import Foundation
import Testing
@testable import UsageDock

@Suite("Usage insights")
struct UsageInsightsTests {
    @Test("Risk follows the scarcest window across providers")
    func riskFollowsScarcestWindow() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 95, windowMinutes: 10_080, resetsAt: nil),
            planName: "max",
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let insights = UsageInsights(claude: claude, codex: nil)

        #expect(insights.minRemainingPercent == 5)
        #expect(insights.riskLevel == .high)
        #expect(insights.constrainingWindow?.windowMinutes == 10_080)
    }

    @Test("Named Claude limits participate in insights without replacing the general week")
    func includesScopedClaudeWindow() throws {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 20, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now,
            scopedWindows: [
                ScopedQuotaWindow(
                    scopeID: "fable",
                    displayName: "Fable",
                    window: QuotaWindow(usedPercent: 30, windowMinutes: 10_080, resetsAt: nil)
                )
            ]
        )
        let windows = UsageInsights(claude: claude, codex: nil).windows

        #expect(windows.count == 3)
        #expect(windows.last?.scopeName == "Fable")
        #expect(windows.last?.id.contains("scope-fable") == true)
    }

    @Test("Scoped model limits stay out of global risk selection")
    func scopedLimitsDoNotDriveGlobalRisk() {
        let codex = ProviderQuota(
            provider: .codex,
            primary: QuotaWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 30, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now,
            scopedWindows: [
                ScopedQuotaWindow(
                    scopeID: "codex_bengalfox",
                    displayName: "GPT-5.3-Codex-Spark",
                    window: QuotaWindow(usedPercent: 99, windowMinutes: 10_080, resetsAt: nil)
                )
            ]
        )
        let insights = UsageInsights(claude: nil, codex: codex)

        #expect(insights.windows.count == 3)
        #expect(insights.minRemainingPercent == 70)
        #expect(insights.riskLevel == .low)
        #expect(insights.constrainingWindow?.scopeName == nil)
    }

    @Test("Provider headline ignores a tighter scoped model limit")
    func providerHeadlineIgnoresScopedModelLimit() throws {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 11, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 28, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now,
            scopedWindows: [
                ScopedQuotaWindow(
                    scopeID: "fable",
                    displayName: "Fable",
                    window: QuotaWindow(usedPercent: 52, windowMinutes: 10_080, resetsAt: nil)
                )
            ]
        )
        let insights = UsageInsights(claude: claude, codex: nil)
        let headline = try #require(insights.scarcestGeneralWindow(for: .claude))

        #expect(headline.windowMinutes == 10_080)
        #expect(headline.remainingPercent == 72)
        #expect(headline.scopeName == nil)

        let defaultSummary = try #require(
            insights.summaryGeneralWindow(for: .claude, strategy: .shortestWindow)
        )
        #expect(defaultSummary.windowMinutes == 300)
        #expect(defaultSummary.remainingPercent == 89)

        let tightestSummary = try #require(
            insights.summaryGeneralWindow(for: .claude, strategy: .lowestRemaining)
        )
        #expect(tightestSummary.windowMinutes == 10_080)
        #expect(tightestSummary.remainingPercent == 72)
    }

    @Test("Duplicate scoped windows from an old snapshot appear only once")
    func deduplicatesScopedWindows() {
        let first = ScopedQuotaWindow(
            scopeID: "fable",
            displayName: "Fable",
            window: QuotaWindow(usedPercent: 10, windowMinutes: 10_080, resetsAt: nil)
        )
        let latest = ScopedQuotaWindow(
            scopeID: "FABLE",
            displayName: "Fable",
            window: QuotaWindow(usedPercent: 20, windowMinutes: 10_080, resetsAt: nil)
        )
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 5, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            planName: nil,
            capturedAt: .now,
            scopedWindows: [first, latest]
        )

        let windows = UsageInsights(claude: claude, codex: nil).windows

        #expect(windows.count == 2)
        #expect(windows.last?.usedPercent == 20)
    }

    @Test("Summary identifies the provider behind the lowest remaining quota")
    func constrainingProviderIsExplicit() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 4, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 15, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now
        )
        let codex = ProviderQuota(
            provider: .codex,
            primary: QuotaWindow(usedPercent: 62, windowMinutes: 10_080, resetsAt: nil),
            secondary: nil,
            planName: nil,
            capturedAt: .now
        )
        let insights = UsageInsights(claude: claude, codex: codex)

        #expect(insights.constrainingWindow?.provider == .codex)
        #expect(insights.constrainingWindow?.remainingPercent == 38)
    }

    @Test("Medium and low thresholds map to remaining percentage bands")
    func riskThresholds() {
        #expect(RiskLevel(minRemainingPercent: nil) == .unknown)
        #expect(RiskLevel(minRemainingPercent: 5) == .high)
        #expect(RiskLevel(minRemainingPercent: 25) == .medium)
        #expect(RiskLevel(minRemainingPercent: 60) == .low)
    }

    @Test("No quota yields an unknown, empty state instead of fabricated data")
    func emptyState() {
        let insights = UsageInsights(claude: nil, codex: nil)

        #expect(insights.minRemainingPercent == nil)
        #expect(insights.riskLevel == .unknown)
        #expect(insights.lastUpdated == nil)
    }

    @Test("Last updated is the most recent capture across sources")
    func lastUpdatedIsNewest() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            planName: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let insights = UsageInsights(claude: claude, codex: nil)

        #expect(insights.lastUpdated == Date(timeIntervalSince1970: 1_000))
    }
}
