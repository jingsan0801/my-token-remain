import SwiftUI

/// Full provider quota card: brand row + plan pill, then one row per official
/// window (remaining %, progress bar, reset label). Shown in the Dashboard's
/// Limits section. Renders a waiting state before data arrives.
struct QuotaCard: View {
    /// 所有 provider 共用同一个内容槽位:卡片底边与网格行严格对齐。
    /// 高度按常见内容取(两条窗口 + 重置/更新时间、4 个账号的总览、
    /// Kimi 的 5 小时/周/月三档),真正超出的内容才在卡片内滚动,
    /// 不用单张卡片把整行网格拉高。
    static let dashboardContentHeight: CGFloat = 300
    /// 卡片完整高度(含 `DashboardCard` 内边距),供「添加应用」占位槽
    /// 对齐真实卡片。
    static var dashboardCardHeight: CGFloat {
        dashboardContentHeight + cardPadding * 2
    }
    private static let cardPadding: CGFloat = 13
    /// Reserve one shared title slot for every grid card so quota rows stay
    /// aligned even when a compact connection warning is present.
    private static let headerMinHeight: CGFloat = 26
    private static let contentSpacing: CGFloat = 11

    let provider: ProviderQuota.Provider
    let quota: ProviderQuota?
    var serviceStatus: ProviderServiceStatus?
    /// Provider 级状态说明(如 Cursor 登录过期的恢复提示)。
    var notice: String?
    /// Observe managed-account changes even when the system quota stays nil.
    /// The Dashboard owns this store; cards never create a collector.
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: PreferencesStore = .shared

    /// Managed-account alerts are card-local: renaming and removal must not open
    /// another window or settings route.
    @State private var pendingRenameID: ProviderAccountID?
    @State private var pendingRenameText = ""
    @State private var pendingRemoveID: ProviderAccountID?
    /// Every provider presents its setup requirements before starting login or
    /// accepting a secret, so the compact plus button never triggers a surprise.
    @State private var isPresentingAccountSetup = false
    @State private var pendingCredentialUpdateID: ProviderAccountID?

    /// Dashboard 卡片:目录内的池由通用池开关 + 智能默认决定显隐;
    /// 目录外的池(账户级兄弟池)维持既有行为——恒显。
    @MainActor
    static func scopedWindows(
        in quota: ProviderQuota,
        preferences: PreferencesStore
    ) -> [ScopedQuotaWindow] {
        quota.uniqueScopedWindows.filter { scoped in
            guard let entry = ScopedPoolToggleCatalog.entry(
                for: scoped,
                provider: quota.provider
            ) else {
                return true
            }
            // 活跃度按整个池组判定(见 ScopedPoolToggleCatalog.poolIsActive),
            // 同组多行(如 Spark 的 _session/_weekly)显隐一致,且与设置页
            // 开关读到的智能默认相同。
            return preferences.resolvedScopedPoolVisibility(
                provider: entry.provider,
                poolKey: entry.poolKey,
                poolIsActive: ScopedPoolToggleCatalog.poolIsActive(
                    entry: entry,
                    in: quota
                )
            )
        }
    }

    private var credentialConfiguration: ProviderCredentialConfiguration? {
        guard quota == nil else { return nil }
        return ProviderCredentialConfiguration.resolve(for: provider)
    }

    var body: some View {
        DashboardCard(padding: Self.cardPadding) {
            VStack(alignment: .leading, spacing: Self.contentSpacing) {
                header
                // 内容装得下时直接铺开:不创建内层滚动视图,也就不会
                // 截获页面滚轮;真的超过统一槽位时才退回卡片内滚动。
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: Self.contentSpacing) {
                        quotaContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: Self.contentSpacing) {
                            quotaContent
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .frame(height: Self.dashboardContentHeight, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .alert(
            L10n.text("accounts.rename_title"),
            isPresented: renameAlertPresented,
            presenting: pendingRenameID
        ) { id in
            TextField(L10n.text("accounts.rename_placeholder"), text: $pendingRenameText)
            Button(L10n.text("action.cancel"), role: .cancel) { pendingRenameID = nil }
            Button(L10n.text("action.save")) {
                store.renameProviderAccount(id, to: pendingRenameText)
                pendingRenameID = nil
            }
        } message: { _ in
            Text(L10n.text("accounts.rename_message"))
        }
        .alert(
            L10n.text("accounts.remove_title"),
            isPresented: removeAlertPresented,
            presenting: pendingRemoveID
        ) { id in
            Button(L10n.text("action.cancel"), role: .cancel) { pendingRemoveID = nil }
            Button(L10n.text("accounts.remove_confirm"), role: .destructive) {
                store.removeProviderAccount(id)
                pendingRemoveID = nil
            }
        } message: { id in
            Text(L10n.format(removeMessageKey(for: id), accountName(for: id)))
        }
    }

    /// An isolated CLI account owns a local login folder; a keychain account
    /// owns one Keychain item. Say which one removal actually deletes.
    private func removeMessageKey(for id: ProviderAccountID) -> String {
        let kind = accountSnapshots.first { $0.id == id }?.profile.credentialKind
        return kind == .keychainSecret
            ? "accounts.remove_message_credential"
            : "accounts.remove_message"
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingRenameID != nil },
            set: { if !$0 { pendingRenameID = nil } }
        )
    }

    private var removeAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoveID != nil },
            set: { if !$0 { pendingRemoveID = nil } }
        )
    }

    @ViewBuilder
    private var quotaContent: some View {
        if supportsMultipleAccounts,
           store.isAddingProviderAccount(provider) {
            AccountAddProgressRow(
                credentialKind: multiAccountCapability?.credentialKind,
                deadline: store.accountLoginDeadlines[provider],
                onCancel: { store.cancelProviderAccountLogin(provider) }
            )
        } else if let message = store.accountManagementNotice(for: provider) {
            Label(message, systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(L10n.format("accounts.management_notice", message))
        }

        if showsAccountOverview {
            accountOverview
        } else {
            singleAccountContent
        }
    }

    @ViewBuilder
    private var singleAccountContent: some View {
        if let quota {
            if provider == .codex, let credits = quota.codexResetCredits {
                CodexResetCreditsCard(credits: credits)
                Divider().overlay(DashboardSurface.border)
            }
            QuotaWindowRow(
                window: quota.primary,
                provider: provider,
                attribution: quota.attribution,
                remainingBalance: quota.primary.remainingBalance ?? quota.remainingBalance
            )
            if let secondary = quota.secondary {
                Divider().overlay(DashboardSurface.border)
                QuotaWindowRow(
                    window: secondary,
                    provider: provider,
                    attribution: quota.attribution
                )
            }
            ForEach(
                Self.scopedWindows(in: quota, preferences: preferences),
                id: \.scopeID
            ) { scoped in
                Divider().overlay(DashboardSurface.border)
                QuotaWindowRow(
                    window: scoped.window,
                    provider: provider,
                    attribution: quota.attribution,
                    scopeName: scoped.displayName
                )
            }
            if let extraUsage = quota.extraUsage {
                Divider().overlay(DashboardSurface.border)
                ExtraUsageRow(extraUsage: extraUsage)
            }
            if let balance = quota.accountBalance {
                Divider().overlay(DashboardSurface.border)
                AccountBalanceRow(balance: balance)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // A failed latest refresh means everything on the card is the
                // cached snapshot, even when it is younger than the staleness
                // threshold — say so instead of implying live data.
                let isCached = notice != nil
                let isStale = isCached || context.date.timeIntervalSince(quota.capturedAt) >= 600
                let freshness = UsageFormatting.freshnessDescription(since: quota.capturedAt, now: context.date)
                Label {
                    Text(isCached ? L10n.format("freshness.cached", freshness) : freshness)
                        .numericFont(10)
                } icon: {
                    Image(systemName: isStale ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                }
                .font(.system(size: 10))
                .foregroundStyle(isStale ? DashboardTheme.warning : DashboardTheme.mutedText)
            }
            if let notice {
                Divider().overlay(DashboardSurface.border)
                QuotaNoticeBanner(message: notice)
            }
        } else if let credentialConfiguration {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    L10n.text(
                        credentialConfiguration.isCookie
                            ? "provider.detect.needs_cookie_hint"
                            : "provider.detect.needs_api_key_hint"
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                ProviderCredentialEntryRow(
                    store: store,
                    provider: provider,
                    configuration: credentialConfiguration
                )

                if let notice {
                    Text(notice)
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardTheme.warning)
                        .lineLimit(2)
                        .help(notice)
                }
            }
        } else if notice == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("quota.loading_official"))
                    .font(.system(size: 12))
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }

    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 8) {
                    BrandIcon(provider: provider)
                        .foregroundStyle(DashboardTheme.text)
                        .frame(width: 20, height: 20)
                    Text(provider.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DashboardTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(2)
                }
                .padding(.top, 3)
                .directReorderHandle()

                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                    .contentShape(Rectangle())
                    .directReorderHandle()

                quotaRefreshButton
            }

            // Metadata gets its own row: a narrow grid column cannot fit the
            // provider name, account menu, refresh and plan pill side by side,
            // and hiding any of them behind truncation is worse than one
            // extra line.
            HStack(alignment: .center, spacing: 6) {
                accountControls

                if let serviceStatus, serviceStatus.isAbnormal {
                    ServiceStatusBadge(status: serviceStatus)
                }

                Spacer(minLength: 0)

                if let plan = quota?.planName, !plan.isEmpty {
                    TagPill(text: plan)
                        .directReorderHandle()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.headerMinHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    /// 卡片级手动刷新。拉取范围由 store 按当前账户选择决定;这里只负责
    /// 呈现「正在刷新」并阻止重复点击。放在拖拽把手之外,点击不会触发排序。
    private var quotaRefreshButton: some View {
        let isRefreshing = store.isRefreshingQuota(for: provider)
        return Button {
            Task { await store.refreshQuotaCard(provider) }
        } label: {
            Group {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DashboardTheme.secondaryText)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .padding(.top, 2)
        .help(L10n.format("quota.refresh_named", provider.displayName))
        .accessibilityLabel(L10n.format("quota.refresh_named", provider.displayName))
    }

    // MARK: - Multi-account

    /// The backend decides which providers expose a safe credential boundary.
    /// Providers without one (currently OpenCode and Kiro) keep exactly their
    /// previous header and content, including the absence of an Add button.
    private var multiAccountCapability: ProviderMultiAccountCapability? {
        provider.multiAccountCapability
    }

    private var supportsMultipleAccounts: Bool {
        multiAccountCapability != nil
    }

    /// Non-nil only for providers whose second account is one opaque secret;
    /// isolated-CLI providers sign in through their own official browser flow.
    private var credentialHint: ProviderAccountCredentialHint? {
        guard multiAccountCapability?.credentialKind == .keychainSecret else { return nil }
        return ProviderAccountCredentialHint.resolve(for: provider)
    }

    /// Includes disabled managed accounts on purpose: a paused account must stay
    /// discoverable in the menu even though it leaves the all-account summary.
    private var accountSnapshots: [ProviderAccountSnapshot] {
        guard supportsMultipleAccounts else { return [] }
        return store.accountSnapshots(for: provider)
    }

    private var accountSelection: ProviderAccountSelection {
        store.accountSelection(for: provider)
    }

    private var selectedAccount: ProviderAccountSnapshot? {
        guard case .account(let id) = accountSelection else { return nil }
        return accountSnapshots.first { $0.id == id }
    }

    /// A lone system account keeps the original single-account card. The grouped
    /// summary only earns its space once a second account exists.
    private var showsAccountOverview: Bool {
        guard supportsMultipleAccounts, case .all = accountSelection else { return false }
        return accountSnapshots.count > 1
    }

    private var combinedAccountQuota: CombinedAccountQuota? {
        guard showsAccountOverview,
              let group = try? CombinedAccountQuota.evaluate(accountSnapshots).get(),
              preferences.combinesAccounts(for: provider, group: group) else { return nil }
        return group
    }

    private func visibleCombinedWindows(_ group: CombinedAccountQuota) -> [CombinedAccountQuota.Window] {
        guard let first = accountSnapshots.first(where: { $0.profile.isEnabled && $0.quota != nil })?.quota else {
            return group.windows
        }
        let visibleScopes = Set(Self.scopedWindows(in: first, preferences: preferences).map { "scoped:\($0.scopeID)" })
        return group.windows.filter { !$0.id.hasPrefix("scoped:") || visibleScopes.contains($0.id) }
    }

    private func accountName(for id: ProviderAccountID) -> String {
        accountSnapshots.first { $0.id == id }?.profile.accountDisplayName
            ?? L10n.text("accounts.untitled")
    }

    @ViewBuilder
    private var accountControls: some View {
        if supportsMultipleAccounts {
            HStack(spacing: 5) {
                if accountSnapshots.count > 1 || accountSnapshots.contains(where: { !$0.profile.isSystem }) {
                    accountMenu(store: store)
                }
                addAccountButton(store: store)
            }
            .padding(.top, 2)
            // Anchored to the row rather than the button so the form stays put
            // while the button itself is disabled during verification.
            .popover(isPresented: $isPresentingAccountSetup, arrowEdge: .bottom) {
                if multiAccountCapability?.credentialKind == .isolatedCLI {
                    AddCLIProviderAccountSheet(
                        store: store,
                        provider: provider,
                        isPresented: $isPresentingAccountSetup
                    )
                } else if let hint = credentialHint {
                    AddProviderAccountSheet(
                        store: store,
                        provider: provider,
                        hint: hint,
                        editingProfile: pendingCredentialUpdateID.flatMap { id in
                            accountSnapshots.first { $0.id == id }?.profile
                        },
                        isPresented: $isPresentingAccountSetup
                    )
                }
            }
            .onChange(of: isPresentingAccountSetup) { _, isPresented in
                if !isPresented {
                    pendingCredentialUpdateID = nil
                    store.clearAccountManagementNotice(for: provider)
                }
            }
        }
    }

    private func accountMenu(store: UsageStore) -> some View {
        let selection = accountSelection
        let isAll = selection == .all
        let summary = store.accountSummary(for: provider)
        let label = isAll
            ? L10n.format("accounts.chip_all", combinedAccountQuota?.accountCount ?? summary.accountCount)
            : (selectedAccount?.profile.accountDisplayName ?? L10n.text("accounts.untitled"))

        return Menu {
            Button {
                store.setAccountSelection(.all, for: provider)
            } label: {
                Label(L10n.text("accounts.all"), systemImage: isAll ? "checkmark" : "person.2")
            }
            Divider()
            ForEach(accountSnapshots) { snapshot in
                Menu {
                    accountActions(snapshot, store: store)
                } label: {
                    Label(
                        snapshot.profile.isEnabled
                            ? snapshot.profile.accountDisplayName
                            : L10n.format("accounts.entry_disabled", snapshot.profile.accountDisplayName),
                        systemImage: menuGlyph(for: snapshot, selection: selection)
                    )
                }
            }
            Divider()
            Button {
                addAccount(store: store)
            } label: {
                Label(L10n.text("accounts.add"), systemImage: "plus")
            }
            .disabled(store.isAddingProviderAccount(provider))
        } label: {
            HStack(spacing: 4) {
                if selectedAccount?.isRefreshing == true {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isAll ? "person.2.fill" : "person.crop.circle.fill")
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 78, alignment: .leading)
            }
            .foregroundStyle(DashboardTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DashboardSurface.surface2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DashboardSurface.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.format("accounts.menu_help", provider.displayName))
        .accessibilityLabel(L10n.format("accounts.menu_accessibility", provider.displayName, label))
    }

    private func menuGlyph(
        for snapshot: ProviderAccountSnapshot,
        selection: ProviderAccountSelection
    ) -> String {
        if selection == .account(snapshot.id) { return "checkmark" }
        if !snapshot.profile.isEnabled { return "person.crop.circle.badge.xmark" }
        return "person.crop.circle"
    }

    private func addAccountButton(store: UsageStore) -> some View {
        Button {
            addAccount(store: store)
        } label: {
            Group {
                if store.isAddingProviderAccount(provider) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DashboardTheme.secondaryText)
                }
            }
            .frame(width: 20, height: 18)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DashboardSurface.surface2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DashboardSurface.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isAddingProviderAccount(provider))
        .help(
            store.isAddingProviderAccount(provider)
                ? L10n.text(addingLabelKey)
                : L10n.format(addHelpKey, provider.displayName)
        )
        .accessibilityLabel(L10n.format("accounts.add_accessibility", provider.displayName))
    }

    private var addHelpKey: String {
        multiAccountCapability?.credentialKind == .keychainSecret
            ? "accounts.add_help_credential"
            : "accounts.add_help"
    }

    private var addingLabelKey: String {
        multiAccountCapability?.credentialKind == .keychainSecret
            ? "accounts.adding_credential"
            : "accounts.adding"
    }

    /// The store already guards against a second concurrent add; checking here
    /// too keeps a double click from queueing a redundant sign-in. Isolated-CLI
    /// providers now explain the isolated browser login before it starts;
    /// keychain providers explain exactly which credential will be stored.
    private func addAccount(store: UsageStore) {
        guard !store.isAddingProviderAccount(provider) else { return }
        guard multiAccountCapability != nil else { return }
        pendingCredentialUpdateID = nil
        store.clearAccountManagementNotice(for: provider)
        isPresentingAccountSetup = true
    }

    @ViewBuilder
    private var accountOverview: some View {
        if let group = combinedAccountQuota {
            CombinedAccountControl(provider: provider, snapshots: accountSnapshots, preferences: preferences)
            CombinedAccountQuotaView(group: group, windows: visibleCombinedWindows(group), provider: provider)
            let summary = store.accountSummary(for: provider)
            if summary.lowAccountCount > 0 {
                Text(L10n.format("accounts.summary_low", summary.lowAccountCount))
                    .font(.system(size: 10.5)).foregroundStyle(DashboardTheme.warning)
            }
        } else {
            separateAccountOverview
        }
    }

    @ViewBuilder
    private var separateAccountOverview: some View {
        let summary = store.accountSummary(for: provider)
        let enabled = accountSnapshots.filter(\.profile.isEnabled)

        HStack(spacing: 8) {
            Text(L10n.format(
                "accounts.summary_available",
                summary.availableCount,
                summary.accountCount
            ))
            .numericFont(10.5, .semibold)
            .foregroundStyle(DashboardTheme.secondaryText)
            Spacer(minLength: 6)
            if summary.lowAccountCount > 0 {
                Text(L10n.format("accounts.summary_low", summary.lowAccountCount))
                    .numericFont(10.5, .semibold)
                    .foregroundStyle(DashboardTheme.warning)
            }
            if let lowest = summary.lowestRemainingPercent {
                Text(L10n.format("accounts.summary_lowest", UsageFormatting.percent(lowest)))
                    .numericFont(10.5, .semibold)
                    .foregroundStyle(DashboardTheme.text)
            }
        }

        ForEach(summary.balancesByCurrency.keys.sorted(), id: \.self) { currency in
            HStack {
                Text(L10n.format("accounts.balance_combined", currency))
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.secondaryText)
                Spacer()
                Text(QuotaBalance(
                    amount: summary.balancesByCurrency[currency] ?? 0,
                    currencyCode: currency
                ).displayText)
                .numericFont(11, .semibold)
                .foregroundStyle(DashboardTheme.text)
            }
        }

        // 先给总览读数,再给“是否合并”这类分组控制,视线顺序更贴近
        // 使用顺序:先看还剩多少,再决定怎么归组。
        CombinedAccountControl(provider: provider, snapshots: accountSnapshots, preferences: preferences)

        ForEach(enabled) { snapshot in
            Divider().overlay(DashboardSurface.border)
            AccountDigestRow(
                snapshot: snapshot,
                provider: provider,
                preferences: preferences,
                select: { store.setAccountSelection(.account(snapshot.id), for: provider) }
            )
            .contextMenu { accountActions(snapshot, store: store) }
        }

        if enabled.isEmpty {
            Text(L10n.text("accounts.all_disabled"))
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func accountActions(
        _ snapshot: ProviderAccountSnapshot,
        store: UsageStore
    ) -> some View {
        Button {
            store.setAccountSelection(.account(snapshot.id), for: provider)
        } label: {
            Label(L10n.text("accounts.show_only"), systemImage: "person.crop.circle")
        }
        Button {
            Task { await store.refreshProviderAccount(snapshot.id) }
        } label: {
            Label(L10n.text("action.refresh"), systemImage: "arrow.clockwise")
        }
        .disabled(
            snapshot.isRefreshing
                || !snapshot.profile.isEnabled
                || (snapshot.profile.isSystem && !store.isSystemSourceEnabled(provider))
        )

        // The system account mirrors this Mac's own login for the provider, so
        // TokenRemain must not rename, pause, or delete it.
        if !snapshot.profile.isSystem {
            Divider()
            if snapshot.profile.credentialKind == .keychainSecret {
                Button {
                    pendingCredentialUpdateID = snapshot.id
                    store.clearAccountManagementNotice(for: provider)
                    isPresentingAccountSetup = true
                } label: {
                    Label(L10n.text("accounts.update_credential"), systemImage: "key.fill")
                }
            }
            Button {
                pendingRenameText = snapshot.profile.accountDisplayName
                pendingRenameID = snapshot.id
            } label: {
                Label(L10n.text("accounts.rename"), systemImage: "pencil")
            }
            Button {
                setAccountEnabled(!snapshot.profile.isEnabled, snapshot: snapshot, store: store)
            } label: {
                Label(
                    L10n.text(snapshot.profile.isEnabled ? "accounts.disable" : "accounts.enable"),
                    systemImage: snapshot.profile.isEnabled ? "pause.circle" : "play.circle"
                )
            }
            Divider()
            Button(role: .destructive) {
                pendingRemoveID = snapshot.id
            } label: {
                Label(L10n.text("accounts.remove"), systemImage: "trash")
            }
        }
    }

    /// Pausing the account the card is currently showing would leave the card on
    /// a stale reading, so fall back to the all-account view in the same click.
    private func setAccountEnabled(
        _ enabled: Bool,
        snapshot: ProviderAccountSnapshot,
        store: UsageStore
    ) {
        if !enabled, accountSelection == .account(snapshot.id) {
            store.setAccountSelection(.all, for: provider)
        }
        store.setProviderAccountEnabled(enabled, id: snapshot.id)
    }
}

extension ProviderAccountProfile {
    /// The system account has no stored name and a managed account can only be
    /// renamed to a non-empty string, so this is the single naming fallback.
    var accountDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return L10n.text(isSystem ? "accounts.system" : "accounts.untitled")
    }
}

/// One enabled account inside the all-account view: its own lowest remaining
/// window, independent of whether any sibling account failed. Clicking it opens
/// that account's full quota rows in the same card. Multi-window providers
/// (Kimi's 5-hour/weekly/monthly plan) also list every window here, so the
/// summary does not hide the real constraint.
private struct AccountDigestRow: View {
    let snapshot: ProviderAccountSnapshot
    let provider: ProviderQuota.Provider
    @ObservedObject var preferences: PreferencesStore
    let select: () -> Void

    private struct WindowDigest: Identifiable {
        let id: Int
        let label: String
        let valueText: String
        let remainingPercent: Double
    }

    private var summary: ProviderQuota.GeneralQuotaSummary? {
        snapshot.quota?.generalQuotaSummary(strategy: .lowestRemaining)
    }

    private var valueText: String {
        guard let summary else {
            return L10n.text(snapshot.isRefreshing ? "accounts.refreshing" : "accounts.unavailable")
        }
        return L10n.format(
            "quota.remaining",
            QuotaWindowRow.remainingValueText(
                remainingPercent: summary.remainingPercent,
                remainingBalance: summary.remainingBalance,
                remainingCredits: summary.window.remainingCredits
            )
        )
    }

    private var valueTint: Color {
        guard let summary else {
            return snapshot.isRefreshing ? DashboardTheme.secondaryText : DashboardTheme.warning
        }
        return summary.remainingPercent < 10 ? DashboardTheme.danger : DashboardTheme.text
    }

    private var windowText: String? {
        summary.map { UsageFormatting.windowName(minutes: $0.window.windowMinutes) }
    }

    /// 账户的全部可见窗口,按窗口时长升序。scoped 池仍走通用池开关,
    /// 目录外的账户级兄弟池保持恒显。
    private var windowDigests: [WindowDigest] {
        guard let quota = snapshot.quota else { return [] }
        var entries: [(window: QuotaWindow, name: String?, balance: QuotaBalance?)] = [
            (
                quota.primary,
                quota.primary.poolName,
                quota.primary.remainingBalance ?? quota.remainingBalance
            )
        ]
        if let secondary = quota.secondary {
            entries.append((secondary, secondary.poolName, secondary.remainingBalance))
        }
        for scoped in QuotaCard.scopedWindows(in: quota, preferences: preferences) {
            entries.append((scoped.window, scoped.displayName, scoped.window.remainingBalance))
        }
        return entries.enumerated()
            .sorted {
                ($0.element.window.windowMinutes, $0.offset)
                    < ($1.element.window.windowMinutes, $1.offset)
            }
            .enumerated()
            .map { index, item in
                let remaining = min(100, max(0, 100 - item.element.window.usedPercent))
                return WindowDigest(
                    id: index,
                    label: item.element.name
                        ?? UsageFormatting.windowName(minutes: item.element.window.windowMinutes),
                    valueText: QuotaWindowRow.remainingValueText(
                        remainingPercent: remaining,
                        remainingBalance: item.element.balance,
                        remainingCredits: item.element.window.remainingCredits
                    ),
                    remainingPercent: remaining
                )
            }
    }

    /// 单窗口账户的信息已由右侧「剩余」承载,多窗口才需要第二行明细。
    private var breakdownText: Text? {
        guard windowDigests.count > 1 else { return nil }
        var text = Text("")
        for (index, digest) in windowDigests.enumerated() {
            if index > 0 {
                text = text + Text("   ·   ")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.mutedText)
            }
            text = text + Text(digest.label)
                .font(.system(size: 10.5))
                .foregroundStyle(DashboardTheme.mutedText)
            text = text + Text(" ")
            text = text + Text(digest.valueText)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(
                    digest.remainingPercent < 10 ? DashboardTheme.danger : DashboardTheme.secondaryText
                )
        }
        return text
    }

    private var accessibilityValue: String {
        guard windowDigests.count > 1 else { return valueText }
        let windows = windowDigests
            .map { "\($0.label) \($0.valueText)" }
            .joined(separator: ", ")
        return "\(valueText), \(windows)"
    }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardTheme.mutedText)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(snapshot.profile.accountDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DashboardTheme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let windowText {
                            Text(windowText)
                                .numericFont(10)
                                .foregroundStyle(DashboardTheme.mutedText)
                                .lineLimit(1)
                        }
                        if snapshot.isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else if snapshot.quota == nil, let notice = snapshot.notice, !notice.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(DashboardTheme.warning)
                                .help(notice)
                        }
                        Spacer(minLength: 8)
                    }
                    if let breakdownText {
                        breakdownText
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(valueText)
                    .numericFont(12, .semibold)
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
                    .padding(.top, 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("accounts.row_help"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "accounts.row_accessibility",
                provider.displayName,
                snapshot.profile.accountDisplayName
            )
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(L10n.text("accounts.row_help"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Official browser sign-in runs outside the app and credential checks run
/// against the provider, so the card states plainly which one it is waiting on
/// instead of looking frozen.
struct AccountAddProgressRow: View {
    let credentialKind: ProviderAccountCredentialKind?
    let deadline: Date?
    let onCancel: () -> Void

    private var messageKey: String {
        credentialKind == .keychainSecret || deadline == nil
            ? "accounts.adding_progress_credential"
            : "accounts.adding_progress"
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(messageKey))
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                        Text(L10n.format("accounts.login_remaining", String(format: "%d:%02d", seconds / 60, seconds % 60)))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }
            }
            if deadline != nil {
                Spacer(minLength: 4)
                Button(L10n.text("action.cancel"), action: onCancel)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(messageKey))
    }
}

/// Codex's banked rate-limit reset balance lives inside the Codex quota card so
/// it stays attached to the limit it can restore. The official usage response
/// exposes the banked count but not a per-credit expiry timestamp. OpenAI's
/// documented app-server contract calls `availableCount` authoritative, while
/// actual redemption can still return `nothingToReset` when no window qualifies.
/// Show the balance here and leave redemption eligibility to Codex Usage.
struct CodexResetCreditsCard: View {
    let credits: CodexRateLimitResetCredits

    static let managementURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    var hasAvailableReset: Bool {
        credits.availableCount > 0
    }

    var statusText: String {
        guard credits.availableCount > 0 else {
            return L10n.text("codex.reset_credits.empty")
        }
        return L10n.format("codex.reset_credits.available_balance", credits.availableCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        hasAvailableReset
                            ? DashboardTheme.success
                            : DashboardTheme.mutedText
                    )
                Text(L10n.text("codex.reset_credits.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.text)
                Spacer(minLength: 8)
                Text(statusText)
                    .numericFont(11, .semibold)
                    .foregroundStyle(
                        hasAvailableReset
                            ? DashboardTheme.success
                            : DashboardTheme.secondaryText
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    L10n.text("codex.reset_credits.expiration"),
                    systemImage: "calendar.badge.clock"
                )
                .font(.system(size: 9.5))
                .foregroundStyle(DashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Link(destination: Self.managementURL) {
                    HStack(spacing: 3) {
                        Text(L10n.text("codex.reset_credits.manage"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DashboardTheme.link)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DashboardSurface.surface2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DashboardSurface.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(L10n.text("codex.reset_credits.title")), \(statusText), \(L10n.text("codex.reset_credits.expiration"))"
        )
    }
}

/// 卡片内容区的完整故障/恢复提示。放在额度行之后、多行铺开,不再把
/// 长文案截断成「请在 Cu…」。文案仍是失败自带的本地化消息:固定的
/// 「重新登录」会误标缺 Key、网络错误和第三方登录等不同情况。
private struct QuotaNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DashboardTheme.warning)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DashboardTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DashboardTheme.warning.opacity(0.11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DashboardTheme.warning.opacity(0.42), lineWidth: 1)
        }
        .help(message)
        .accessibilityLabel(message)
    }
}

/// 订阅之外的按量消费行(OpenUsage 的 "Extra Usage $X spent" 式样)。
/// 有月度上限时显示 "已花 / 上限"。
struct ExtraUsageRow: View {
    let extraUsage: ExtraUsage

    private var valueText: String {
        let spent = L10n.format("quota.spent", UsageFormatting.compactUSD(extraUsage.spentUSD))
        guard let limit = extraUsage.monthlyLimitUSD else { return spent }
        return "\(spent) / \(UsageFormatting.compactUSD(limit))"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.text("quota.extra_usage"))
                .font(.system(size: 12))
                .usageDockAdaptiveForeground(.secondary)
            Spacer(minLength: 8)
            Text(valueText)
                .numericFont(12, .semibold)
                .usageDockAdaptiveForeground(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

// Fork note: 自用版不再展示官方花费(成本)与按模型的 token 用量明细,
// ProviderSpendRow / ProviderModelUsageRow 已随界面移除。
struct AccountBalanceRow: View {
    let balance: QuotaBalance

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.text("quota.account_balance"))
                .font(.system(size: 12))
                .usageDockAdaptiveForeground(.secondary)
            Spacer(minLength: 8)
            Text(balance.displayText)
                .numericFont(12, .semibold)
                .usageDockAdaptiveForeground(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A single quota window inside a `QuotaCard`.
struct QuotaWindowRow: View {
    let window: QuotaWindow
    let provider: ProviderQuota.Provider
    var attribution: QuotaAttribution? = nil
    var showsDetails = true
    var scopeName: String?
    var remainingBalance: QuotaBalance? = nil

    /// Scoped rows are named by their call site; a general window can also
    /// name itself when it represents one pool of a split cycle (Cursor).
    private var effectiveScopeName: String? {
        scopeName ?? window.poolName
    }

    private var remainingPercent: Double {
        min(100, max(0, 100 - window.usedPercent))
    }

    var body: some View {
        // 行级 60 秒一跳足够驱动分钟级倒计时;常驻桌面的浮窗
        // 不该为秒针每秒重排整行。最后一小时的秒级滚动由重置标签内部
        // 的局部 TimelineView 单独承担。
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: showsDetails ? 7 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    if let sourceProvider = attribution?.provider,
                       sourceProvider != provider {
                        BrandIcon(provider: sourceProvider)
                            .frame(width: 12, height: 12)
                            .usageDockAdaptiveForeground(.secondary)
                    }
                    Text(windowTitle)
                        .font(.system(size: 13))
                        .usageDockAdaptiveForeground(.secondary)
                    Spacer()
                    Text(remainingText)
                        .numericFont(14, .bold)
                        .usageDockAdaptiveForeground(.primary)
                }

                SegmentBar(
                    value: remainingPercent / 100,
                    accent: DashboardTheme.quotaAccent(
                        for: attribution?.provider ?? provider,
                        remainingPercent: remainingPercent
                    )
                )

                if showsDetails {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        if let resetsAt = window.resetsAt {
                            QuotaResetLabel(resetsAt: resetsAt, referenceDate: context.date)
                                .layoutPriority(1)
                        } else {
                            Text(L10n.text("quota.reset_pending"))
                                .layoutPriority(1)
                        }
                    }
                    .font(.system(size: 10))
                    .usageDockAdaptiveForeground(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.snappy(duration: 0.22), value: showsDetails)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "quota.window_accessibility",
                accessibilityProviderName,
                windowAccessibilityDescriptor
            )
        )
        .accessibilityValue(remainingText)
    }

    private var remainingText: String {
        L10n.format(
            "quota.remaining",
            Self.remainingValueText(
                remainingPercent: remainingPercent,
                remainingBalance: remainingBalance ?? window.remainingBalance,
                remainingCredits: window.remainingCredits
            )
        )
    }

    static func remainingValueText(
        remainingPercent: Double,
        remainingBalance: QuotaBalance?,
        remainingCredits: Double? = nil
    ) -> String {
        if let credits = remainingCredits, credits.isFinite, credits >= 0 {
            return L10n.format("alibaba.credits", credits)
        }
        return remainingBalance?.displayText ?? UsageFormatting.percent(remainingPercent)
    }

    private var windowTitle: String {
        Self.displayTitle(
            windowMinutes: window.windowMinutes,
            scopeName: effectiveScopeName,
            attribution: attribution
        )
    }

    static func displayTitle(
        windowMinutes: Int,
        scopeName: String?,
        attribution: QuotaAttribution?
    ) -> String {
        let duration = L10n.format("quota.window", UsageFormatting.windowName(minutes: windowMinutes))
        let scoped = scopeName.map { "\($0) · \(duration)" } ?? duration
        guard let source = attribution?.displayName else { return scoped }
        return "\(source) · \(scoped)"
    }

    private var windowAccessibilityDescriptor: String {
        let duration = UsageFormatting.windowName(minutes: window.windowMinutes)
        return effectiveScopeName.map { "\($0) · \(duration)" } ?? duration
    }

    private var accessibilityProviderName: String {
        guard let source = attribution?.displayName else { return provider.displayName }
        return "\(provider.displayName) · \(source)"
    }
}

/// 重置时间标签。距重置不足一小时才以秒级滚动倒计时;此时它是整个
/// 卡片里唯一按 1 秒刷新的叶子视图,重排被限制在这一小段文本内。
/// 一小时以上按分钟粒度显示,由外层 60 秒时间线驱动即可。
private struct QuotaResetLabel: View {
    let resetsAt: Date
    /// 外层 60 秒时间线的当前时刻,同时决定秒级/分钟级两种模式的切换。
    let referenceDate: Date

    var body: some View {
        if UsageFormatting.showsLiveSecondCountdown(to: resetsAt, now: referenceDate) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(UsageFormatting.resetDescription(to: resetsAt, now: context.date))
                    .numericFont(10)
            }
        } else {
            Text(UsageFormatting.resetDescription(to: resetsAt, now: referenceDate))
                .numericFont(10)
        }
    }
}
