import Foundation
import Testing
@testable import UsageDock

@Suite("Adaptive provider refresh policy")
struct AdaptiveRefreshPolicyTests {
    @Test("Local sessions stay live while idle account polling has a five-minute floor")
    func localAIIntervals() {
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: 300,
            lowLatencySyncEnabled: false,
            localSessionActive: true,
            primarySurfaceVisible: false
        ) == 60)
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: 60,
            lowLatencySyncEnabled: false,
            localSessionActive: false,
            primarySurfaceVisible: false
        ) == 300)
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: 1_800,
            lowLatencySyncEnabled: false,
            localSessionActive: false,
            primarySurfaceVisible: false
        ) == 1_800)
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: nil,
            lowLatencySyncEnabled: true,
            localSessionActive: false,
            primarySurfaceVisible: false
        ) == 300)
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: nil,
            lowLatencySyncEnabled: true,
            localSessionActive: true,
            primarySurfaceVisible: false
        ) == 60)
        #expect(AdaptiveRefreshPolicy.localAIQuotaInterval(
            preferred: nil,
            lowLatencySyncEnabled: false,
            localSessionActive: true,
            primarySurfaceVisible: false
        ) == nil)
    }

    @Test("Scheduler and Codex scans slow down only when both sessions and UI are idle")
    func schedulerIntervals() {
        #expect(AdaptiveRefreshPolicy.schedulerInterval(
            localSessionActive: true,
            primarySurfaceVisible: false,
            auxiliaryQuotaInterval: 1_800
        ) == 60)
        #expect(AdaptiveRefreshPolicy.schedulerInterval(
            localSessionActive: false,
            primarySurfaceVisible: true,
            auxiliaryQuotaInterval: nil
        ) == 60)
        #expect(AdaptiveRefreshPolicy.schedulerInterval(
            localSessionActive: false,
            primarySurfaceVisible: false,
            auxiliaryQuotaInterval: nil
        ) == 300)
        #expect(AdaptiveRefreshPolicy.schedulerInterval(
            localSessionActive: false,
            primarySurfaceVisible: false,
            auxiliaryQuotaInterval: 60
        ) == 60)
        #expect(AdaptiveRefreshPolicy.codexLocalSnapshotInterval(
            localSessionActive: false,
            primarySurfaceVisible: false
        ) == 300)
    }

    @Test("Unrelated providers retain the user's cadence")
    func auxiliaryIntervals() {
        #expect(AdaptiveRefreshPolicy.auxiliaryQuotaInterval(
            preferred: 60,
            lowLatencySyncEnabled: false
        ) == 60)
        #expect(AdaptiveRefreshPolicy.auxiliaryQuotaInterval(
            preferred: nil,
            lowLatencySyncEnabled: false
        ) == nil)
        #expect(AdaptiveRefreshPolicy.auxiliaryQuotaInterval(
            preferred: nil,
            lowLatencySyncEnabled: true
        ) == 300)
    }

    @Test("Provider errors back off independently and cap at five minutes")
    func cappedBackoff() {
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 0) == 0)
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 1) == 60)
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 2) == 120)
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 3) == 240)
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 4) == 300)
        #expect(AdaptiveRefreshPolicy.retryDelay(after: 9) == 300)
    }

    @Test("Claude fallback failures double from their base delay and cap at thirty minutes")
    func escalatedBackoff() {
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 300, consecutiveFailures: 1) == 300)
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 300, consecutiveFailures: 2) == 600)
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 300, consecutiveFailures: 3) == 1200)
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 300, consecutiveFailures: 4) == 1800)
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 300, consecutiveFailures: 9) == 1800)
        // 服务端 Retry-After 直接作为首次底数时同样不被放大到第一档以下。
        #expect(AdaptiveRefreshPolicy.escalatedRetryDelay(base: 60, consecutiveFailures: 1) == 60)
    }

    #if TOKENREMAIN_CLOUD_SYNC
    @Test("Sync fingerprint ignores capture-only churn but detects quota changes")
    func contentFingerprint() {
        let start = Date(timeIntervalSince1970: 1_784_764_800)
        func quota(
            usedPercent: Double,
            capturedAt: Date,
            balance: Double = 10
        ) -> ProviderQuota {
            ProviderQuota(
                provider: .claude,
                primary: QuotaWindow(
                    usedPercent: usedPercent,
                    windowMinutes: 300,
                    resetsAt: start + 300,
                    remainingBalance: QuotaBalance(amount: balance, currencyCode: "USD")
                ),
                secondary: nil,
                planName: "Pro",
                capturedAt: capturedAt
            )
        }
        let first = SyncContentFingerprint.make(
            quotas: [.claude: quota(usedPercent: 42, capturedAt: start)],
            history: nil,
            includesUsageHistory: false
        )
        let recaptured = SyncContentFingerprint.make(
            quotas: [.claude: quota(usedPercent: 42, capturedAt: start + 60)],
            history: nil,
            includesUsageHistory: false
        )
        let changed = SyncContentFingerprint.make(
            quotas: [.claude: quota(usedPercent: 43, capturedAt: start + 60)],
            history: nil,
            includesUsageHistory: false
        )
        let balanceChanged = SyncContentFingerprint.make(
            quotas: [.claude: quota(
                usedPercent: 42,
                capturedAt: start + 60,
                balance: 9
            )],
            history: nil,
            includesUsageHistory: false
        )
        #expect(first == recaptured)
        #expect(first != changed)
        #expect(first != balanceChanged)
    }
    #endif
}

@Suite("Transport failure notice suppression")
struct TransportFailureNoticeSuppressionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A fresh cached snapshot keeps a transport failure silent")
    func freshSnapshotStaysSilent() {
        #expect(AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-90),
            now: now,
            refreshInterval: 60
        ))
    }

    @Test("The grace period is two refresh rounds but never under ten minutes")
    func gracePeriodScalesWithInterval() {
        // Minute-level refresh: ten-minute floor applies.
        #expect(AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-9 * 60),
            now: now,
            refreshInterval: 60
        ))
        #expect(!AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-11 * 60),
            now: now,
            refreshInterval: 60
        ))
        // Thirty-minute refresh: an hour of silence.
        #expect(AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-55 * 60),
            now: now,
            refreshInterval: 30 * 60
        ))
        #expect(!AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-61 * 60),
            now: now,
            refreshInterval: 30 * 60
        ))
        // Manual-only refresh falls back to the idle cadence.
        #expect(AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(-9 * 60),
            now: now,
            refreshInterval: nil
        ))
    }

    @Test("No snapshot or a clock-skewed snapshot always surfaces the failure")
    func missingOrFutureSnapshotSurfaces() {
        #expect(!AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: nil,
            now: now,
            refreshInterval: 60
        ))
        #expect(!AdaptiveRefreshPolicy.suppressesTransportFailureNotice(
            cachedCapturedAt: now.addingTimeInterval(120),
            now: now,
            refreshInterval: 60
        ))
    }
}
