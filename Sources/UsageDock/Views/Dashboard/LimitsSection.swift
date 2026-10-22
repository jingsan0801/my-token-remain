import SwiftUI

/// Dashboard Limits: the authoritative view of every official quota window,
/// reusing the popover's `QuotaCard`. Pure live data. Providers that are not
/// connected yet render their onboarding hint inside the card instead of an
/// endless spinner. Providers that require a pasted API key or cookie expose
/// that setup directly in the empty quota card.
struct LimitsSection: View {
    private static let reorderCoordinateSpace = "tokenremain.dashboard.limits.direct-reorder"

    let insights: UsageInsights
    var serviceStatuses: [ProviderQuota.Provider: ProviderServiceStatus] = [:]
    @ObservedObject var store: UsageStore
    @ObservedObject var tracked: TrackedProvidersStore = .shared
    let reorderInteraction: DirectReorderInteraction<ProviderQuota.Provider>

    /// Multi-account providers read the store's selection-aware projection;
    /// single-account providers keep using the original insights snapshot.
    private func quota(for provider: ProviderQuota.Provider) -> ProviderQuota? {
        guard provider.multiAccountCapability != nil else { return insights.quota(for: provider) }
        return store.displayedQuota(for: provider)
    }

    private func notice(for provider: ProviderQuota.Provider) -> String? {
        store.cardNotice(for: provider)
    }

    /// 全部刷新:复用整轮刷新入口,强制拉取每个已追踪 provider 的额度。
    /// 本地用量不在这里重复触发,额度页只关心额度快照。
    private var refreshAllButton: some View {
        Button {
            Task { await store.refresh(force: true) }
        } label: {
            HStack(spacing: 5) {
                if store.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(L10n.text("limits.refresh_all"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(DashboardTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(DashboardSurface.surface2)
            }
            .overlay {
                Capsule().stroke(DashboardSurface.border, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing || !store.manuallyRefreshingProviders.isEmpty)
        .help(L10n.text("limits.refresh_all_help"))
        .accessibilityLabel(L10n.text("limits.refresh_all"))
    }

    private enum GridEntry: Hashable {
        case provider(ProviderQuota.Provider)
        case addProvider
    }

    /// A plain row layout instead of `LazyVGrid`: resizing the dashboard with
    /// several glass cards used to send the lazy grid into a measurement loop
    /// (100% CPU, unresponsive window). Two/three columns keep the original
    /// widths; the gap between the thresholds stops the page scrollbar from
    /// flipping the column count back and forth.
    @State private var columnCount = 2

    private var gridEntries: [GridEntry] {
        var entries = tracked.enabledOrdered.map(GridEntry.provider)
        if !tracked.disabledOrdered.isEmpty {
            entries.append(.addProvider)
        }
        return entries
    }

    private var entryRows: [[GridEntry]] {
        let entries = gridEntries
        let columns = max(1, columnCount)
        return stride(from: 0, to: entries.count, by: columns).map { start in
            Array(entries[start..<min(start + columns, entries.count)])
        }
    }

    private func updateColumnCount(for width: CGFloat) {
        let target: Int
        if width >= 940 {
            target = 3
        } else if width <= 900 {
            target = 2
        } else {
            target = columnCount
        }
        guard target != columnCount else { return }
        columnCount = target
    }

    @ViewBuilder
    private func quotaCard(_ provider: ProviderQuota.Provider) -> some View {
        QuotaCard(
            provider: provider,
            quota: quota(for: provider),
            serviceStatus: serviceStatuses[provider],
            notice: notice(for: provider),
            store: store
        )
            .directReorder(
                item: provider,
                candidates: tracked.enabledOrdered,
                coordinateSpace: Self.reorderCoordinateSpace,
                interaction: reorderInteraction,
                layout: .grid(spacing: 14),
                move: { source, target in
                    tracked.move(source, to: target)
                }
            )
            .help(L10n.text("quota.drag_help"))
            .accessibilityHint(L10n.text("quota.drag_accessibility"))
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation(.snappy) { tracked.setEnabled(provider, false) }
                } label: {
                    Label(L10n.format("limits.stop_tracking_named", provider.displayName), systemImage: "minus.circle")
                }
            }
            .zIndex(reorderInteraction.isDragging(provider) ? 10_000 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitleHeader(
                title: DashboardSection.limits.title,
                subtitle: DashboardSection.limits.subtitle,
                trailing: insights.lastUpdated.map { L10n.format("common.updated_at", $0.formatted(date: .omitted, time: .standard)) }
            ) {
                refreshAllButton
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(entryRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(row, id: \.self) { entry in
                            switch entry {
                            case .provider(let provider):
                                quotaCard(provider)
                                    .frame(maxWidth: .infinity, alignment: .top)
                            case .addProvider:
                                AddProviderTile(tracked: tracked)
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                        ForEach(0..<max(0, columnCount - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                updateColumnCount(for: width)
            }
        }
        .coordinateSpace(name: Self.reorderCoordinateSpace)
    }
}

/// 「添加应用」虚线卡片:列出未追踪的应用与它们的检测状态,
/// 点一下即加入追踪(与卡片右键"停止追踪"互为镜像)。
private struct AddProviderTile: View {
    @ObservedObject var tracked: TrackedProvidersStore

    private var detections: [TrackedProvidersStore.Detection] {
        TrackedProvidersStore.detections().filter { !tracked.isEnabled($0.provider) }
    }

    var body: some View {
        Menu {
            ForEach(detections) { detection in
                Button {
                    withAnimation(.snappy) { tracked.setEnabled(detection.provider, true) }
                } label: {
                    Label(
                        detection.installed
                            ? L10n.format("limits.provider_detected", detection.provider.displayName)
                            : L10n.format("limits.provider_not_detected", detection.provider.displayName),
                        systemImage: detection.installed ? "checkmark.circle" : "circle.dashed"
                    )
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
                Text(L10n.text("limits.add_app"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.text)
                Text(L10n.text("limits.add_app_subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        DashboardSurface.border,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.text("limits.add_app_accessibility"))
    }
}
