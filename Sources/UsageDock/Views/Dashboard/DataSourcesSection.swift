import SwiftUI

/// Dashboard Data Sources: live status of each local source UsageDock reads,
/// automatic local-app discovery plus explicit credential setup where required,
/// any current error surfaced verbatim, and the privacy posture. All real.
/// Fork note: 自用版移除了 token 用量/成本,ccusage、本地用量来源、
/// Trae 目录与 Claude 日志目录等本地用量数据源不再出现在本页。
struct DataSourcesSection: View {
    @ObservedObject var store: UsageStore
    let insights: UsageInsights
    @ObservedObject var feedStore: AIFeedStore
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitleHeader(
                title: DashboardSection.dataSources.title,
                subtitle: DashboardSection.dataSources.subtitle
            )

            DashboardCard {
                VStack(alignment: .leading, spacing: 0) {
                    PanelHeader(title: L10n.text("datasource.status_title"))
                        .padding(.bottom, 4)
                    Text(L10n.text("datasource.visibility_note"))
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                    if visibleSources.isEmpty {
                        Text(L10n.text("datasource.none_connected"))
                            .font(.system(size: 12))
                            .foregroundStyle(DashboardTheme.mutedText)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                    } else {
                        ForEach(visibleSources, id: \.self) { source in
                            if source != visibleSources.first {
                                rowDivider
                            }
                            sourceRow(source)
                        }
                    }
                }
            }
            if let errorMessage {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.text("datasource.diagnostics_title"), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DashboardTheme.warning)
                        Text(errorMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    PanelHeader(title: L10n.text("privacy.title"))
                    RoadmapList(items: [
                        L10n.text("privacy.local_only"),
                        L10n.text("privacy.readonly_credentials"),
                        L10n.text("privacy.zai_key"),
                        L10n.text("privacy.feed_managed")
                    ])
                }
            }
        }
    }

    private enum VisibleSource: Hashable {
        case provider(ProviderQuota.Provider)
        case feed
    }

    /// Provider 保留持久化的成功连接历史，同时让当前追踪的手动凭据型
    /// 来源在首次连接前就显示输入框。
    private var visibleSources: [VisibleSource] {
        var sources = store.dataSourceProviders.map(VisibleSource.provider)
        if feedStore.lastUpdated != nil { sources.append(.feed) }
        return sources
    }

    @ViewBuilder
    private func sourceRow(_ source: VisibleSource) -> some View {
        switch source {
        case .provider(let provider):
            let quota = insights.quota(for: provider)
            SourceHealthRow(
                name: sourceName(for: provider),
                detail: store.providerNotices[provider] ?? sourceDetail(for: provider),
                healthy: quota != nil && store.providerNotices[provider] == nil,
                capturedAt: quota?.capturedAt,
                disabled: !store.isSystemSourceEnabled(provider)
            )
            providerCredentialRow(for: provider)
        case .feed:
            SourceHealthRow(
                name: L10n.text("datasource.feed_name"),
                detail: feedSourceDetail,
                healthy: true,
                capturedAt: feedStore.lastUpdated
            )
        }
    }

    @ViewBuilder
    private func providerCredentialRow(for provider: ProviderQuota.Provider) -> some View {
        switch provider {
        case .claude, .codex:
            ProviderAuthorizationRow(store: store, provider: provider)
            if provider == .claude, let configuration = ProviderCredentialConfiguration.resolve(for: provider) {
                ProviderCredentialEntryRow(store: store, provider: provider, configuration: configuration)
                    .padding(.top, 8)
            }
        default:
            if let configuration = ProviderCredentialConfiguration.resolve(for: provider) {
                ProviderCredentialEntryRow(
                    store: store,
                    provider: provider,
                    configuration: configuration
                )
                .padding(.top, 8)
                .padding(.leading, 20)
            }
        }
    }

    private func sourceName(for provider: ProviderQuota.Provider) -> String {
        switch provider {
        case .claude: return "Claude Code"
        case .grok: return L10n.text("datasource.name_grok")
        case .zai: return L10n.text("datasource.name_zai")
        case .zaiTeam: return "GLM Team"
        case .thirdParty: return L10n.text("datasource.name_third_party")
        default: return provider.displayName
        }
    }

    private func sourceDetail(for provider: ProviderQuota.Provider) -> String {
        switch provider {
        case .claude: return L10n.text("datasource.detail.claude")
        case .codex: return L10n.text("datasource.detail.codex")
        case .cursor: return L10n.text("datasource.detail.cursor")
        case .copilot: return L10n.text("datasource.detail.copilot")
        case .devin: return L10n.text("datasource.detail.devin")
        case .windsurf: return L10n.text("datasource.detail.windsurf")
        case .grok: return L10n.text("datasource.detail.grok")
        case .grokBot: return L10n.text("datasource.detail.grok_bot")
        case .openrouter: return L10n.text("datasource.detail.openrouter")
        case .antigravity: return L10n.text("datasource.detail.antigravity")
        case .opencode: return L10n.text("datasource.detail.opencode")
        case .zai: return L10n.text("datasource.detail.zai")
        case .zaiTeam: return L10n.text("datasource.detail.zai_team")
        case .thirdParty: return L10n.text("datasource.detail.third_party")
        case .kiro: return L10n.text("datasource.detail.kiro")
        case .ollama: return L10n.text("datasource.detail.ollama")
        default: return L10n.text("datasource.detail.default")
        }
    }

    private var rowDivider: some View {
        Divider().overlay(DashboardSurface.border).padding(.vertical, 12)
    }

    private var feedSourceDetail: String {
        feedStore.lastUpdated == nil
            ? L10n.text("datasource.feed_waiting")
            : L10n.text("datasource.feed_active")
    }
}

/// Claude/Codex 的凭证归官方客户端所有。这里只提供两种显式操作：
/// 允许 TokenRemain 发起一次只读钥匙串读取，或打开官方应用完成登录/续期。
private struct ProviderAuthorizationRow: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderQuota.Provider
    @StateObject private var action = AsyncViewAction()
    private var isAuthorizing: Bool { action.isRunning }

    private var appName: String {
        switch provider {
        case .codex: "ChatGPT / Codex"
        default: provider.displayName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(
                    isAuthorizing
                        ? L10n.text("datasource.authorizing")
                        : L10n.text("datasource.authorize_read")
                ) {
                    action.start {
                        _ = await store.authorizeProviderCredentials(provider)
                    }
                }
                .disabled(isAuthorizing)

                if isAuthorizing {
                    Button(L10n.text("action.cancel")) { action.cancel() }
                }

                // Claude's desktop app keeps its sign-in to itself, so opening it
                // never restores Claude Code's login; the Cookie setup below is
                // the in-app alternative. Codex's app does share its login.
                if provider != .claude, ProviderDesktopAppService.applicationURL(for: provider) != nil {
                    Button(L10n.format("datasource.open_provider_app", appName)) {
                        ProviderDesktopAppService.open(provider)
                    }
                }
            }
            .controlSize(.small)

            Text(L10n.text("datasource.authorization_note"))
                .font(.system(size: 10))
                .foregroundStyle(DashboardTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .padding(.leading, 20)
        .onDisappear { action.cancel() }
    }
}

private struct SourceHealthRow: View {
    let name: String
    let detail: String
    let healthy: Bool
    let capturedAt: Date?
    var disabled: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(
                    disabled
                        ? DashboardTheme.mutedText
                        : (healthy ? DashboardTheme.success : DashboardTheme.warning)
                )
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(
                    disabled
                        ? L10n.text("accounts.management.stopped")
                        : (healthy ? L10n.text("datasource.healthy") : L10n.text("datasource.broken"))
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        disabled
                            ? DashboardTheme.mutedText
                            : (healthy ? DashboardTheme.success : DashboardTheme.warning)
                    )
                if let capturedAt {
                    Text(capturedAt.formatted(date: .omitted, time: .shortened))
                        .numericFont(10)
                        .foregroundStyle(DashboardTheme.mutedText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
