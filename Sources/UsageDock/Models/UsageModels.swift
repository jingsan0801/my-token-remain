import Foundation

struct QuotaWindow: Sendable, Codable {
    let usedPercent: Double
    let windowMinutes: Int
    /// Claude can report a freshly-reset window before it knows the next reset time.
    /// Keep that official "unknown" state instead of carrying forward an expired date.
    let resetsAt: Date?
    /// Some providers expose a monetary cap for each individual window. The
    /// percentage still drives the meter; this replaces only the remaining text.
    var remainingBalance: QuotaBalance? = nil
    /// Cursor splits one billing cycle into named pools ("Cursor Models" /
    /// "Other Models"). When the primary window is one such pool rather than
    /// the whole account, this names it so rows stay distinguishable from the
    /// sibling pool carried as a scoped window.
    var poolName: String? = nil
    /// Non-monetary Token Plan credits. Optional for old cache compatibility.
    /// Deliberately excluded from the current mobile wire format.
    var remainingCredits: Double? = nil
}

/// A monetary remainder reported or derived for one quota window. The meter
/// still uses `QuotaWindow.usedPercent`; this replaces only its remaining text.
struct QuotaBalance: Sendable, Codable, Equatable {
    let amount: Double
    let currencyCode: String

    var displayText: String {
        let normalizedCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let symbol = switch normalizedCode {
        case "CNY", "JPY": "¥"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        default: normalizedCode.isEmpty ? "" : "\(normalizedCode) "
        }
        let safeAmount = amount.isFinite ? max(0, amount) : 0
        return "\(symbol)\(String(format: "%.2f", safeAmount))"
    }
}

/// A provider-specific quota that shares a duration with a general window but
/// applies to a named model or product scope (for example Claude's Fable cap).
struct ScopedQuotaWindow: Sendable, Codable {
    let scopeID: String
    let displayName: String
    let window: QuotaWindow
    /// When a live source last reported this window. Optional so snapshots
    /// written by older builds still decode — they decode as `nil`, which
    /// `retainingActiveScopedWindows` treats as expired rather than immortal.
    var observedAt: Date? = nil

    var isFable: Bool {
        scopeID.lowercased().hasPrefix("fable")
            || displayName.localizedCaseInsensitiveContains("Fable")
    }

    var isCodexSpark: Bool {
        // Codex 模型池的 scoped 窗口现在成对携带 `_session` / `_weekly`
        // 后缀(见 CodexUsageService.scopedWindows),精确比较会漏掉带
        // 后缀的窗口,这里用前缀匹配保住 Spark 显示开关。
        scopeID.lowercased().hasPrefix("codex_bengalfox")
            || displayName.localizedCaseInsensitiveContains("Codex-Spark")
    }

    var isAntigravityThirdParty: Bool {
        scopeID.lowercased().hasPrefix("antigravity_3p_")
    }

    /// Is this a model name, or a chunk of screen the parser mistook for one?
    ///
    /// A real fossil found in a live cache had this as its `displayName`:
    ///
    ///     Fable
    ///     ████████████████████    40%used
    ///     Resets Aug14 at 12:59pm(Asia/Shanghai
    ///
    /// with `usedPercent: 0`, so the popup rendered that blob as a row title
    /// reading `100% remaining` next to the real `Fable` at 98% used. An older
    /// parser swallowed the progress bar and reset line into the label, and the
    /// entry then survived every refresh (see `retainingActiveScopedWindows`).
    /// Fixing the parser does not help anyone who already has one cached, so
    /// the corrupt shape is rejected wherever a scoped window enters the app.
    var isPlausibleModelScope: Bool {
        guard !scopeID.isEmpty, !displayName.isEmpty else { return false }
        // No real model name spans lines or carries drawing glyphs.
        guard !displayName.contains(where: { $0.isNewline }) else { return false }
        guard displayName.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !("\u{2500}"..."\u{259F}").contains(scalar)
        }) else { return false }
        // `Fable`, `GPT-5.3-Codex-Spark`. Screen fragments blow past this.
        return displayName.count <= 48 && scopeID.count <= 32
    }

    /// Claude Code names the general weekly cap `Current week (all models)`.
    /// It is the same value as the secondary window, never a model-scoped one,
    /// so a reading carrying that label must not become an extra card.
    var isGeneralWeeklyLabel: Bool {
        Self.isGeneralWeeklyLabel(scopeID) || Self.isGeneralWeeklyLabel(displayName)
    }

    /// Terminal repainting drops glyphs from the label — `all odels`,
    /// `ll models`, and a copy captured before the trailing `s` painted all
    /// reach the parser. Accept any spelling that is still `all models` with up
    /// to two characters missing; no real model name survives that test.
    static func isGeneralWeeklyLabel(_ name: String) -> Bool {
        let reference = "allmodels"
        let normalized = name.lowercased().filter { $0.isASCII && $0.isLetter }
        guard normalized.count >= reference.count - 2 else { return false }
        var index = normalized.startIndex
        for character in reference where index < normalized.endIndex {
            if normalized[index] == character {
                index = normalized.index(after: index)
            }
        }
        return index == normalized.endIndex
    }
}

/// 订阅限额之外的按量付费消费(Claude 的 extra usage credits)。
struct ExtraUsage: Sendable, Codable, Equatable {
    let spentUSD: Double
    /// 月度上限;未设上限时为 nil。
    let monthlyLimitUSD: Double?
}

/// Saved Codex rate-limit resets reported by ChatGPT's usage service. OpenAI's
/// documented `account/rateLimits/read` contract calls `availableCount`
/// authoritative. The private wham response can also contain an undocumented
/// `applicable_available_count`; do not persist or interpret it as UI state.
struct CodexRateLimitResetCredits: Sendable, Codable, Equatable {
    let availableCount: Int
}

/// Identifies the account/API that actually owns a quota while preserving the
/// host application as `ProviderQuota.provider`. For example, Claude Code can
/// remain the card identity while its balance is attributed to DeepSeek API.
/// Only a normalized route identifier is cached; credentials and full URLs are
/// deliberately excluded from this model.
struct QuotaAttribution: Sendable, Codable, Equatable {
    let provider: ProviderQuota.Provider?
    let displayName: String
    let routeIdentifier: String
}

/// Chooses which account-wide window represents a provider on compact summary
/// surfaces. Named model/pool limits are never candidates for either strategy.
enum QuotaSummaryStrategy: String, CaseIterable, Identifiable, Sendable {
    case shortestWindow
    case lowestRemaining

    var id: String { rawValue }
}

struct ProviderQuota: Sendable, Codable {
    struct GeneralQuotaSummary: Sendable {
        let window: QuotaWindow
        let remainingPercent: Double
        let remainingBalance: QuotaBalance?
    }

    let provider: Provider
    let primary: QuotaWindow
    let secondary: QuotaWindow?
    let planName: String?
    let capturedAt: Date
    var extraUsage: ExtraUsage? = nil
    /// A provider-wide wallet that is distinct from any individual rate-limit
    /// window. Kept out of mobile sync until the shared schema has an explicit
    /// balance field instead of overloading duplicate zero-minute windows.
    var accountBalance: QuotaBalance? = nil
    /// Optional so existing cached snapshots decode without a schema migration.
    var scopedWindows: [ScopedQuotaWindow]? = nil
    /// Legacy primary-window field retained so existing caches stay compatible.
    /// New multi-window data belongs on each `QuotaWindow`.
    var remainingBalance: QuotaBalance? = nil
    /// Codex-only banked resets. Nil means the current source did not expose the
    /// official reset-credit fields; zero is a real, successfully fetched count.
    var codexResetCredits: CodexRateLimitResetCredits? = nil
    /// Nil means the quota belongs to the host provider itself. A non-nil value
    /// names the API account that supplied the displayed limit or balance.
    var attribution: QuotaAttribution? = nil

    /// The shortest account-wide window is the default compact/headline value.
    /// This preserves the historical 5-hour-first behavior while keeping named
    /// model or pool limits out of every account-level summary.
    var generalQuotaSummary: GeneralQuotaSummary {
        generalQuotaSummary(strategy: .shortestWindow)
    }

    func generalQuotaSummary(strategy: QuotaSummaryStrategy) -> GeneralQuotaSummary {
        let primarySummary = GeneralQuotaSummary(
            window: primary,
            remainingPercent: Self.remainingPercent(for: primary),
            remainingBalance: primary.remainingBalance ?? remainingBalance
        )
        guard let secondary else { return primarySummary }

        let secondarySummary = GeneralQuotaSummary(
            window: secondary,
            remainingPercent: Self.remainingPercent(for: secondary),
            remainingBalance: secondary.remainingBalance
        )
        switch strategy {
        case .shortestWindow:
            let primaryDuration = Self.summaryDuration(primarySummary.window.windowMinutes)
            let secondaryDuration = Self.summaryDuration(secondarySummary.window.windowMinutes)
            return secondaryDuration < primaryDuration ? secondarySummary : primarySummary
        case .lowestRemaining:
            if secondarySummary.remainingPercent == primarySummary.remainingPercent {
                return Self.summaryDuration(secondarySummary.window.windowMinutes)
                    < Self.summaryDuration(primarySummary.window.windowMinutes)
                    ? secondarySummary
                    : primarySummary
            }
            return secondarySummary.remainingPercent < primarySummary.remainingPercent
                ? secondarySummary
                : primarySummary
        }
    }

    private static func summaryDuration(_ minutes: Int) -> Int {
        minutes > 0 ? minutes : .max
    }

    private static func remainingPercent(for window: QuotaWindow) -> Double {
        guard window.usedPercent.isFinite else { return 100 }
        return min(100, max(0, 100 - window.usedPercent))
    }

    /// Terminal repainting and older cached snapshots can contain the same
    /// model-scoped quota more than once. Keep the latest reading for each
    /// stable scope while preserving the service's original display order.
    /// Damaged `all models` labels are dropped here rather than only at parse
    /// time, so a snapshot cached before the parser learned to reject them
    /// stops rendering phantom cards on the next launch.
    var uniqueScopedWindows: [ScopedQuotaWindow] {
        var order: [String] = []
        var latestByScope: [String: ScopedQuotaWindow] = [:]
        // Every consumer reads scoped windows through here, so this is the one
        // place that can also clean a cache written by an older, buggier parse.
        for scoped in scopedWindows ?? []
        where !scoped.isGeneralWeeklyLabel && scoped.isPlausibleModelScope {
            let key = scoped.scopeID.lowercased()
            if latestByScope[key] == nil {
                order.append(key)
            }
            latestByScope[key] = scoped
        }
        return order.compactMap { latestByScope[$0] }
    }

    /// Claude currently names this model-scoped weekly cap `fable`, but keep
    /// the lookup tolerant of a future version suffix such as `fable_5`.
    var fableWindow: ScopedQuotaWindow? {
        uniqueScopedWindows.first(where: \.isFable)
    }

    /// Keeps the authoritative primary/all-model values while filling model-
    /// scoped windows from a secondary source such as Claude Code's `/usage`
    /// screen. Current-source entries win if both sources report the same ID.
    func mergingScopedWindows(_ supplemental: [ScopedQuotaWindow]) -> ProviderQuota {
        var order: [String] = []
        var latestByScope: [String: ScopedQuotaWindow] = [:]
        for scoped in supplemental + uniqueScopedWindows {
            let key = scoped.scopeID.lowercased()
            if latestByScope[key] == nil {
                order.append(key)
            }
            latestByScope[key] = scoped
        }
        let merged = order.compactMap { latestByScope[$0] }
        return ProviderQuota(
            provider: provider,
            primary: primary,
            secondary: secondary,
            planName: planName,
            capturedAt: capturedAt,
            extraUsage: extraUsage,
            accountBalance: accountBalance,
            scopedWindows: merged.isEmpty ? nil : merged,
            remainingBalance: remainingBalance,
            codexResetCredits: codexResetCredits,
            attribution: attribution
        )
    }

    /// Re-hosts an API provider's quota under the application that consumed it.
    /// The billing source remains explicit so UI and caches never imply that a
    /// DeepSeek/OpenRouter balance is an official Claude or Codex allowance.
    func attributed(
        to hostProvider: Provider,
        source: QuotaAttribution
    ) -> ProviderQuota {
        ProviderQuota(
            provider: hostProvider,
            primary: primary,
            secondary: secondary,
            planName: planName,
            capturedAt: capturedAt,
            extraUsage: extraUsage,
            accountBalance: accountBalance,
            scopedWindows: scopedWindows,
            remainingBalance: remainingBalance,
            codexResetCredits: codexResetCredits,
            attribution: source
        )
    }

    /// A general account refresh can succeed while the secondary `/usage`
    /// probe temporarily omits model-scoped rows. Preserve the previous
    /// window only while the source snapshot is younger than fifteen minutes
    /// and still belongs to the current quota cycle. Per-window stale metadata
    /// does not exist, so dropping an older value is safer than presenting it
    /// as authoritative. A current scoped value still wins when merging.
    func retainingActiveScopedWindows(
        from previous: ProviderQuota,
        now: Date,
        staleRetention: TimeInterval = 900
    ) -> ProviderQuota {
        // Retention exists for one narrow case: the account refresh succeeded
        // but the secondary `/usage` probe happened to omit model-scoped rows
        // this round. If THIS snapshot already carries scoped windows, the
        // source did report its set, and anything missing from it is genuinely
        // gone — resurrecting the previous set would only keep dead rows alive.
        guard uniqueScopedWindows.isEmpty else { return self }

        // `previous.capturedAt` cannot anchor staleness: every refresh re-saves
        // the merged snapshot with a fresh timestamp, so a carried-forward
        // window kept resetting its own clock and lived forever. A live cache
        // held a corrupt Fable row this way for an entire quota cycle, shown as
        // `100% remaining` beside the real one at 98% used. Anchor on when the
        // window was actually observed instead, and treat a window from an
        // older build (no timestamp) as expired rather than immortal.
        let active = previous.uniqueScopedWindows.filter { scoped in
            guard let observedAt = scoped.observedAt,
                  now.timeIntervalSince(observedAt) < staleRetention else {
                return false
            }
            if let resetsAt = scoped.window.resetsAt {
                // `> now` alone kept a corrupt reset alive forever: a damaged
                // `/usage` line once parsed into the same date a year out, and
                // a year-out timestamp satisfies that test for the whole cycle.
                // A reset can never sit further out than its own window is long.
                let interval = resetsAt.timeIntervalSince(now)
                let window = TimeInterval(max(0, scoped.window.windowMinutes)) * 60
                return interval > 0 && (window == 0 || interval <= window + 300)
            }
            return true
        }
        return mergingScopedWindows(active)
    }

    enum Provider: String, Sendable, Codable, Hashable {
        case claude = "Claude Code"
        case codex = "Codex"
        case cursor = "Cursor"
        case grok = "Grok"
        case grokBot = "Grok Bot"
        case zai = "Z.ai"
        case zaiTeam = "GLM Team"
        case copilot = "Copilot"
        case devin = "Devin"
        case windsurf = "Windsurf"
        case openrouter = "OpenRouter"
        case antigravity = "Antigravity"
        case opencode = "OpenCode"
        case deepseek = "DeepSeek"
        case kimi = "Kimi"
        case minimax = "MiniMax"
        case mimo = "MiMo Code"
        case alibabaTokenPlan = "Alibaba Token Plan"
        case qoder = "Qoder"
        case kiro = "Kiro"
        case volcengine = "Volcengine"
        case ollama = "Ollama"
        case muse = "Muse"
        case museCode = "Muse Code"
        case amp = "Amp"
        case factory = "Factory"
        case augment = "Augment"
        case thirdParty = "Third-party APIs"

        /// UI 展示与遍历用的稳定顺序(nonisolated,供任何上下文使用)。
        static let displayOrder: [Provider] = [
            .claude, .codex, .cursor, .copilot, .devin, .windsurf,
            .grok, .grokBot, .openrouter, .antigravity, .opencode, .zai, .zaiTeam,
            .deepseek, .kimi, .minimax, .mimo, .alibabaTokenPlan, .qoder,
            .kiro, .volcengine, .ollama, .muse, .museCode, .amp, .factory, .augment, .thirdParty
        ]

        /// UI 里的短名(rawValue 保留历史值以兼容缓存/持久化)。
        var displayName: String {
            switch self {
            case .claude: return "Claude"
            case .codex: return "Codex"
            case .cursor: return "Cursor"
            case .grok: return "Grok"
            case .grokBot: return "Grok Bot"
            case .zai: return "Z.ai"
            case .zaiTeam: return "GLM Team"
            case .copilot: return "Copilot"
            case .devin: return "Devin"
            case .windsurf: return "Windsurf"
            case .openrouter: return "OpenRouter"
            case .antigravity: return "Antigravity"
            case .opencode: return "OpenCode"
            case .deepseek: return "DeepSeek"
            case .kimi: return "Kimi"
            case .minimax: return "MiniMax"
            case .mimo: return "MiMo"
            case .alibabaTokenPlan: return "Bailian"
            case .qoder: return "Qoder"
            case .kiro: return "Kiro"
            case .volcengine: return "Volcengine"
            case .ollama: return "Ollama"
            case .muse: return "Muse"
            case .museCode: return "Muse Code"
            case .amp: return "Amp"
            case .factory: return "Factory"
            case .augment: return "Augment"
            case .thirdParty: return "Third-party"
            }
        }
    }
}


