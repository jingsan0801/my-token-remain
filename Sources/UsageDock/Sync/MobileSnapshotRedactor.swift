import Foundation
import TokenRemainSyncKit

/// The only path from macOS provider models into the cross-device payload.
/// Keep this conversion explicit: adding fields to `ProviderQuota` must never
/// make them cross devices automatically.
enum MobileSnapshotRedactor {
    static let maximumLifetime: TimeInterval = 24 * 60 * 60

    /// Every quota provider rendered by the current phone client. This list is
    /// presentation-independent and remains an explicit privacy boundary: only
    /// normalized quota windows, timestamps, source state and a sanitized plan
    /// label cross devices; credentials and raw provider responses never do.
    static let publishedProviders: [ProviderQuota.Provider] = ProviderQuota.Provider.displayOrder.filter {
        SyncedProviderID.supportedOnCurrentMobile.contains(stableID(for: $0))
    }

    static func makeSnapshot(
        from quotas: [ProviderQuota.Provider: ProviderQuota],
        sourceInstanceID: UUID,
        sequence: UInt64,
        generatedAt: Date = Date()
    ) -> MobileUsageSnapshot {
        let providers = publishedProviders.compactMap { provider in
            quotas[provider].map(redact)
        }

        return MobileUsageSnapshot(
            sourceInstanceID: sourceInstanceID,
            sequence: sequence,
            generatedAt: generatedAt,
            expiresAt: generatedAt.addingTimeInterval(maximumLifetime),
            providers: providers,
            aggregateUsage: nil,
            // Fork note: 自用版不再采集 token 用量/成本,快照不再携带用量历史。
            dailyUsageHistory: nil,
            curatedFeed: nil
        )
    }

    private static func redact(_ quota: ProviderQuota) -> SyncedProviderQuota {
        let windows = [quota.primary, quota.secondary]
            .compactMap { $0 }
            .enumerated()
            .map { index, window in
                let balance = window.remainingBalance ?? (index == 0 ? quota.remainingBalance : nil)
                return SyncedQuotaWindow(
                    usedPercent: min(max(window.usedPercent, 0), 100),
                    windowMinutes: max(0, window.windowMinutes),
                    resetsAt: window.resetsAt,
                    remainingBalance: balance.map {
                        SyncedQuotaBalance(amount: $0.amount, currencyCode: $0.currencyCode)
                    },
                    // A pool label that fails wire sanitization is dropped, not
                    // rejected: the window's numbers are still correct without it.
                    poolName: SyncedQuotaWindow.sanitizedPoolName(window.poolName)
                )
            }
        let scopedWindows = quota.uniqueScopedWindows.compactMap { scoped -> SyncedScopedQuotaWindow? in
            // Cached PTY output from an older parser can contain a partial
            // repaint where the model label absorbs progress-bar/reset lines.
            // The mobile wire label is deliberately stricter than arbitrary
            // desktop UI text. Drop only that damaged scoped row so one bad
            // optional model limit cannot reject every provider in the snapshot.
            guard let scopeID = wireScopeID(for: scoped), isWireSafe(scoped) else { return nil }
            return SyncedScopedQuotaWindow(
                scopeID: scopeID,
                displayName: scoped.displayName,
                window: SyncedQuotaWindow(
                    usedPercent: min(max(scoped.window.usedPercent, 0), 100),
                    windowMinutes: max(0, scoped.window.windowMinutes),
                    resetsAt: scoped.window.resetsAt,
                    remainingBalance: scoped.window.remainingBalance.map {
                        SyncedQuotaBalance(amount: $0.amount, currencyCode: $0.currencyCode)
                    },
                    poolName: SyncedQuotaWindow.sanitizedPoolName(scoped.window.poolName)
                )
            )
        }
        // Transport validation enforces windows.count + scopedWindows.count <=
        // maximumWindowsPerProvider and rejects the whole snapshot on overflow.
        // A provider with several model pools (Codex now emits a session+weekly
        // pair per pool) can legitimately exceed that, so truncate the scoped
        // tail deterministically — the list is already in the service's semantic
        // order, so the rows that survive are stable across refreshes. Better to
        // drop trailing optional model rows than to let one busy provider get
        // every provider's snapshot rejected.
        let scopedCapacity = max(0, maximumSyncedWindowsPerProvider - windows.count)
        let cappedScopedWindows = Array(scopedWindows.prefix(scopedCapacity))
        return SyncedProviderQuota(
            providerID: stableID(for: quota.provider),
            windows: windows,
            capturedAt: quota.capturedAt,
            statusCode: .available,
            planName: SyncedProviderQuota.sanitizedPlanName(quota.planName),
            scopedWindows: cappedScopedWindows.isEmpty ? nil : cappedScopedWindows
        )
    }

    /// The transport-validation window budget shared by `windows` and
    /// `scopedWindows`. Read from the default configuration so the redactor can
    /// never disagree with what `validatedForTransport` will enforce.
    static var maximumSyncedWindowsPerProvider: Int {
        SyncValidationConfiguration.current().maximumWindowsPerProvider
    }

    static func isWireSafe(_ scoped: ScopedQuotaWindow) -> Bool {
        guard wireScopeID(for: scoped) != nil else { return false }
        return SyncedProviderQuota.sanitizedPlanName(scoped.displayName) == scoped.displayName
    }

    static func wireScopeID(for scoped: ScopedQuotaWindow) -> String? {
        let normalized = scoped.scopeID.lowercased()
        let scopeBytes = normalized.utf8
        guard (1...32).contains(scopeBytes.count),
              scopeBytes.allSatisfy({ byte in
                  (byte >= 97 && byte <= 122) ||
                      (byte >= 48 && byte <= 57) ||
                      byte == 45 || byte == 95
              }) else {
            return nil
        }
        return normalized
    }

    /// Stable, presentation-independent identifiers. Never derive these from
    /// rawValue/displayName, because those are UI and cache compatibility data.
    static func stableID(for provider: ProviderQuota.Provider) -> String {
        switch provider {
        case .claude: "claude"
        case .codex: "codex"
        case .cursor: "cursor"
        case .grok: "grok"
        // Desktop-only until published consumers support this provider.
        case .grokBot: "grok-bot"
        case .zai: "zai"
        case .zaiTeam: "zaiteam"
        case .copilot: "copilot"
        case .devin: "devin"
        case .windsurf: "windsurf"
        case .openrouter: "openrouter"
        case .antigravity: "antigravity"
        case .opencode: "opencode"
        case .deepseek: "deepseek"
        case .kimi: "kimi"
        case .minimax: "minimax"
        case .mimo: "mimo"
        // Desktop-only until published consumers support this provider.
        case .alibabaTokenPlan: "alibaba-token-plan"
        case .qoder: "qoder"
        case .kiro: "kiro"
        case .volcengine: "volcengine"
        case .ollama: "ollama"
        // Desktop-only: not in SyncedProviderID.supportedOnCurrentMobile.
        case .muse: "muse"
        case .museCode: "muse-code"
        case .amp: "amp"
        case .factory: "factory"
        case .augment: "augment"
        case .thirdParty: "thirdparty"
        }
    }
}
