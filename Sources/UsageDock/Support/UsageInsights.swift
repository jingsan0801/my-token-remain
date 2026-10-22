import Foundation
import SwiftUI

/// Pure, view-independent derivations over the data UsageStore already holds.
///
/// Fork note: 自用版移除了 token 用量/成本/趋势,这里只从各 provider 的
/// 官方额度快照派生风险与摘要,不再包含 ccusage 本地统计与配速预测。
struct UsageInsights {
    /// 各 provider 当前快照,键缺失即无数据。
    let quotasByProvider: [ProviderQuota.Provider: ProviderQuota]

    init(
        claude: ProviderQuota?,
        codex: ProviderQuota?,
        cursor: ProviderQuota? = nil,
        grok: ProviderQuota? = nil,
        zai: ProviderQuota? = nil,
        others: [ProviderQuota] = []
    ) {
        var map: [ProviderQuota.Provider: ProviderQuota] = [:]
        for quota in [claude, codex, cursor, grok, zai].compactMap({ $0 }) + others {
            map[quota.provider] = quota
        }
        quotasByProvider = map
    }

    var claude: ProviderQuota? { quotasByProvider[.claude] }
    var codex: ProviderQuota? { quotasByProvider[.codex] }
    var cursor: ProviderQuota? { quotasByProvider[.cursor] }
    var grok: ProviderQuota? { quotasByProvider[.grok] }
    var zai: ProviderQuota? { quotasByProvider[.zai] }

    func quota(for provider: ProviderQuota.Provider) -> ProviderQuota? {
        quotasByProvider[provider]
    }

    /// 全部直查 provider 的现有快照,固定顺序。
    var quotas: [ProviderQuota] {
        ProviderQuota.Provider.displayOrder.compactMap { quotasByProvider[$0] }
    }

    // MARK: - Quota windows

    struct Window: Identifiable {
        let id: String
        let provider: ProviderQuota.Provider
        let windowMinutes: Int
        let usedPercent: Double
        let remainingPercent: Double
        let resetsAt: Date?
        let scopeName: String?
        let attribution: QuotaAttribution?

        var displayName: String {
            guard let source = attribution?.displayName else { return provider.displayName }
            return "\(provider.displayName) · \(source)"
        }

        var accentProvider: ProviderQuota.Provider {
            attribution?.provider ?? provider
        }
    }

    /// Every official window currently known, in provider then primary→secondary order.
    var windows: [Window] {
        var result: [Window] = []
        for quota in quotas {
            result.append(window(
                quota.primary,
                provider: quota.provider,
                slot: "primary",
                attribution: quota.attribution
            ))
            if let secondary = quota.secondary {
                result.append(window(
                    secondary,
                    provider: quota.provider,
                    slot: "secondary",
                    attribution: quota.attribution
                ))
            }
            for scoped in quota.uniqueScopedWindows {
                result.append(window(
                    scoped.window,
                    provider: quota.provider,
                    slot: "scope-\(scoped.scopeID)",
                    scopeName: scoped.displayName,
                    attribution: quota.attribution
                ))
            }
        }
        return result
    }

    /// Scoped model/pool limits remain inspectable in quota detail, but they
    /// never become a provider's headline or the app-wide status signal. This
    /// keeps optional Fable, Spark, MiniMax model lanes, and third-party pools
    /// from repainting the general provider quota shown across summary surfaces.
    var generalWindows: [Window] {
        windows.filter { $0.scopeName == nil }
    }

    /// The general account window with the least quota remaining for a provider.
    /// Summary surfaces use this instead of selecting from `windows`, which also
    /// contains named model limits such as Claude Fable.
    func scarcestGeneralWindow(for provider: ProviderQuota.Provider) -> Window? {
        generalWindows
            .filter { $0.provider == provider }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    /// The account-wide window chosen for provider summary UI. Risk continues
    /// to use `scarcestGeneralWindow` independently of this display preference.
    func summaryGeneralWindow(
        for provider: ProviderQuota.Provider,
        strategy: QuotaSummaryStrategy
    ) -> Window? {
        let candidates = generalWindows.filter { $0.provider == provider }
        switch strategy {
        case .shortestWindow:
            return candidates.min {
                let lhs = $0.windowMinutes > 0 ? $0.windowMinutes : .max
                let rhs = $1.windowMinutes > 0 ? $1.windowMinutes : .max
                return lhs < rhs
            }
        case .lowestRemaining:
            return candidates.min {
                if $0.remainingPercent == $1.remainingPercent {
                    let lhs = $0.windowMinutes > 0 ? $0.windowMinutes : .max
                    let rhs = $1.windowMinutes > 0 ? $1.windowMinutes : .max
                    return lhs < rhs
                }
                return $0.remainingPercent < $1.remainingPercent
            }
        }
    }

    private func window(
        _ source: QuotaWindow,
        provider: ProviderQuota.Provider,
        slot: String,
        scopeName: String? = nil,
        attribution: QuotaAttribution? = nil
    ) -> Window {
        Window(
            id: "\(provider.rawValue)-\(slot)-\(source.windowMinutes)",
            provider: provider,
            windowMinutes: source.windowMinutes,
            usedPercent: min(100, max(0, source.usedPercent)),
            remainingPercent: min(100, max(0, 100 - source.usedPercent)),
            resetsAt: source.resetsAt,
            scopeName: scopeName,
            attribution: attribution
        )
    }

    // MARK: - Risk

    /// Lowest remaining percentage across every known window, or `nil` when no
    /// official quota has been read yet.
    var minRemainingPercent: Double? {
        generalWindows.map(\.remainingPercent).min()
    }

    /// The window that defines the current risk (the scarcest one).
    var constrainingWindow: Window? {
        generalWindows.min(by: { $0.remainingPercent < $1.remainingPercent })
    }

    var riskLevel: RiskLevel {
        riskLevel(at: .now)
    }

    func riskLevel(at now: Date) -> RiskLevel {
        RiskLevel(minRemainingPercent: minRemainingPercent)
    }

    /// The soonest upcoming reset among all windows that report one.
    var soonestReset: Date? {
        windows.compactMap(\.resetsAt).min()
    }

    // MARK: - Freshness

    /// Most recent capture time across every live source.
    var lastUpdated: Date? {
        quotas.map(\.capturedAt).max()
    }
}
