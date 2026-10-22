import SwiftUI

/// Dashboard Overview: risk-first KPI plus live official quotas.
/// Fork note: 自用版移除了 token 用量、成本预估与"预计可用多久"等
/// 配速/趋势内容,这里只保留额度剩余与风险信息。
struct OverviewSection: View {
    let insights: UsageInsights
    @ObservedObject var preferences: PreferencesStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitleHeader(
                title: DashboardSection.overview.title,
                subtitle: DashboardSection.overview.subtitle,
                trailing: updatedText
            )

            kpiRow

            LazyVGrid(columns: overviewPanelColumns, alignment: .leading, spacing: DashboardOverviewLayout.gridSpacing) {
                officialQuotaPanel
                riskDetailPanel
            }
        }
    }

    private var updatedText: String? {
        insights.lastUpdated.map { L10n.format("common.updated_at", $0.formatted(date: .omitted, time: .standard)) }
    }

    private var overviewPanelColumns: [GridItem] {
        [
            GridItem(
                .flexible(minimum: 280),
                spacing: DashboardOverviewLayout.gridSpacing,
                alignment: .top
            ),
            GridItem(.flexible(minimum: 280), alignment: .top)
        ]
    }

    // MARK: - KPI

    private var kpiRow: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let risk = insights.riskLevel(at: context.date)

            HStack(alignment: .top, spacing: 13) {
                MetricCard(
                    label: L10n.text("overview.kpi.min_remaining"),
                    value: insights.minRemainingPercent.map { UsageFormatting.percent($0) } ?? "—",
                    caption: "\(risk.badge) RISK",
                    captionColor: risk.tint,
                    valueColor: risk == .unknown ? DashboardTheme.text : risk.tint
                )
            }
        }
    }

    // MARK: - Official quota (real, live)

    private var officialQuotaPanel: some View {
        OverviewPanelCard(contentSpacing: 10) {
            PanelHeader(title: L10n.text("quota.official_title"), subtitle: L10n.text("quota.official_subtitle")) {
                TagPill(text: "LIVE", color: DashboardTheme.codex, background: DashboardTheme.surface2)
            }
        } content: {
            let rows = officialQuotaProviders.compactMap { summaryWindow(for: $0) }

            if rows.isEmpty {
                EmptyStateView(
                    icon: "gauge.with.dots.needle.bottom.0percent",
                    title: L10n.text("quota.loading_official_title"),
                    message: L10n.text("quota.loading_official_message")
                )
            } else {
                ForEach(rows) { window in
                    OfficialQuotaRow(window: window)
                }
                Divider().overlay(DashboardSurface.border)
                HStack {
                    Text(L10n.text("overview.risk_level"))
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.secondaryText)
                    Spacer()
                    PixelBadge(
                        text: insights.riskLevel.badge,
                        color: insights.riskLevel.tint,
                        filled: insights.riskLevel == .high
                    )
                }
            }
        }
    }

    /// 今日 token 用量最高的两个 provider;没有本地统计时默认 Claude / Codex。
    /// 排名靠前但没有官方额度快照的候选会被顺延,保证只要有数据就凑满两行。
    private var officialQuotaProviders: [ProviderQuota.Provider] {
        var candidates = insights.providersByTokenUsage
        let fallbacks = [ProviderQuota.Provider.claude, .codex] + insights.quotas.map(\.provider)
        for fallback in fallbacks where !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        return Array(candidates.filter { summaryWindow(for: $0) != nil }.prefix(2))
    }

    private func summaryWindow(for provider: ProviderQuota.Provider) -> UsageInsights.Window? {
        insights.summaryGeneralWindow(
            for: provider,
            strategy: preferences.quotaSummaryStrategy
        )
    }

    // MARK: - Risk detail (real)

    private var riskDetailPanel: some View {
        OverviewPanelCard(contentSpacing: 6, scrollsContent: false) {
            PanelHeader(title: L10n.text("overview.risk_panel_title"), subtitle: L10n.text("overview.risk_panel_subtitle"))
        } content: {
            let now = Date()
            let risk = insights.riskLevel(at: now)

            HStack(spacing: 7) {
                PixelBadge(text: risk.badge, color: risk.tint, filled: risk == .high)
                Text(risk.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DashboardTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(risk.summary)
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let window = insights.constrainingWindow {
                Divider().overlay(DashboardSurface.border)
                InfoRow(
                    label: L10n.text("overview.scarcest_window"),
                    value: "\(window.displayName) · \(UsageFormatting.windowName(minutes: window.windowMinutes))",
                    fontSize: 11
                )
                InfoRow(
                    label: L10n.text("overview.remaining_quota"),
                    value: UsageFormatting.percent(window.remainingPercent),
                    valueColor: risk.tint,
                    fontSize: 11
                )
                if let reset = window.resetsAt {
                    InfoRow(
                        label: L10n.text("overview.projected_reset"),
                        value: UsageFormatting.resetDescription(to: reset),
                        fontSize: 11
                    )
                }
            }
        }
    }
}

/// A provider's selected account-level window shown as a mini progress summary.
private struct OfficialQuotaRow: View {
    let window: UsageInsights.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                BrandIcon(provider: window.provider)
                    .frame(width: 18, height: 18)
                Text(window.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Spacer()
                Text(UsageFormatting.percent(window.remainingPercent))
                    .numericFont(13, .bold)
                    .foregroundStyle(DashboardTheme.text)
            }
            SegmentBar(
                value: window.remainingPercent / 100,
                accent: DashboardTheme.quotaAccent(
                    for: window.accentProvider,
                    remainingPercent: window.remainingPercent
                ),
                height: 5
            )
            HStack {
                Text(L10n.format("quota.window", UsageFormatting.windowName(minutes: window.windowMinutes)))
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardTheme.mutedText)
                Spacer()
                if let reset = window.resetsAt {
                    Text(UsageFormatting.resetDescription(to: reset))
                        .numericFont(10)
                        .foregroundStyle(DashboardTheme.mutedText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("quota.provider_remaining", window.displayName, UsageFormatting.percent(window.remainingPercent)))
    }
}
