import Foundation

/// Keeps refresh work proportional to the chance that quota data changed.
/// Active local Codex/Claude sessions and visible UI retain minute-level
/// freshness. Once both are idle, expensive scans and account requests fall
/// back to at least five minutes instead of keeping an idle Mac on a
/// one-minute work loop.
enum AdaptiveRefreshPolicy {
    static let activeInterval: TimeInterval = 60
    static let idleInterval: TimeInterval = 5 * 60
    static let maximumBackoff: TimeInterval = 5 * 60
    /// 传输类失败的静默期下限。
    static let transportFailureGraceMinimum: TimeInterval = 10 * 60

    /// 传输类失败(请求超时、连接断开)会自己恢复,而卡片会继续渲染上一份
    /// 快照。快照仍在刷新节奏之内时,一次抖动不值得挂出错误直到下一轮
    /// 成功;只有缓存已经明显过时,用户才需要知道数据停了。
    /// 静默期 = 两轮刷新间隔,且不短于十分钟:分钟级刷新下一次抖动
    /// 不出声,三十分钟档下一小时内不出声。
    static func suppressesTransportFailureNotice(
        cachedCapturedAt: Date?,
        now: Date,
        refreshInterval: TimeInterval?
    ) -> Bool {
        guard let cachedCapturedAt else { return false }
        let grace = max(2 * (refreshInterval ?? idleInterval), transportFailureGraceMinimum)
        let age = now.timeIntervalSince(cachedCapturedAt)
        return age >= 0 && age < grace
    }

    static func localAIQuotaInterval(
        preferred: TimeInterval?,
        localSessionActive: Bool,
        primarySurfaceVisible: Bool
    ) -> TimeInterval? {
        if localSessionActive || primarySurfaceVisible {
            guard let preferred else { return nil }
            return min(preferred, activeInterval)
        }
        guard let preferred else { return nil }
        return max(preferred, idleInterval)
    }

    /// Providers unrelated to local Codex/Claude work keep the cadence the user
    /// selected.
    static func auxiliaryQuotaInterval(preferred: TimeInterval?) -> TimeInterval? {
        preferred
    }

    /// The inexpensive activity probe remains minute-level so a newly started
    /// session is noticed promptly. Full local-AI work runs only every five
    /// minutes when there is no visible surface or recent local session, while
    /// enabled auxiliary providers still retain the cadence selected by the
    /// user.
    static func schedulerInterval(
        localSessionActive: Bool,
        primarySurfaceVisible: Bool,
        auxiliaryQuotaInterval: TimeInterval?
    ) -> TimeInterval {
        let localAIInterval = (localSessionActive || primarySurfaceVisible)
            ? activeInterval
            : idleInterval
        guard let auxiliaryQuotaInterval else { return localAIInterval }
        return min(localAIInterval, auxiliaryQuotaInterval)
    }

    static func codexLocalSnapshotInterval(
        localSessionActive: Bool,
        primarySurfaceVisible: Bool
    ) -> TimeInterval {
        (localSessionActive || primarySurfaceVisible) ? activeInterval : idleInterval
    }

    static func retryDelay(after failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let exponent = min(failureCount - 1, 8)
        return min(activeInterval * pow(2, Double(exponent)), maximumBackoff)
    }

    /// Claude 降级链的失败(尤其 PTY 探针超时)每次要付出最多 30 秒的
    /// 进程成本,持续性故障(登出、CLI 界面变化)下固定 5 分钟仍过于
    /// 频繁:以服务错误自带的首次延迟为底数按连续次数翻倍,上限半小时。
    static let escalatedMaximumBackoff: TimeInterval = 30 * 60

    static func escalatedRetryDelay(
        base: TimeInterval,
        consecutiveFailures: Int
    ) -> TimeInterval {
        guard consecutiveFailures > 1 else { return base }
        let exponent = min(consecutiveFailures - 1, 4)
        return min(base * pow(2, Double(exponent)), escalatedMaximumBackoff)
    }

}
