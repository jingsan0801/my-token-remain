import SwiftUI

/// WebDAV 配置同步设置卡。Fork 自有功能:账号配置与本 App 持有的凭证按
/// 用户明确选择以明文 JSON 上传到用户自己的 WebDAV 服务(HTTPS 传输)。
struct WebDAVSyncSettingsCard: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var sync = ConfigSyncController.shared

    @State private var passwordDraft = ""
    @State private var pendingImport: ConfigSyncPayload?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(
                    title: L10n.text("webdav.title"),
                    subtitle: L10n.text("webdav.subtitle")
                )

                Text(L10n.text("webdav.plaintext_notice"))
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                fieldRow(title: L10n.text("webdav.server_url")) {
                    TextField(
                        ConfigSyncController.defaultServerURL,
                        text: $sync.serverURL
                    )
                    .onSubmit { sync.saveSettings(password: nil) }
                }
                fieldRow(title: L10n.text("webdav.account")) {
                    TextField("you@example.com", text: $sync.account)
                        .onSubmit { sync.saveSettings(password: nil) }
                }
                fieldRow(title: L10n.text("webdav.password")) {
                    SecureField(L10n.text("webdav.password_placeholder"), text: $passwordDraft)
                        .onSubmit { sync.saveSettings(password: passwordDraft) }
                }
                fieldRow(title: L10n.text("webdav.remote_root")) {
                    TextField(ConfigSyncController.defaultRemoteRoot, text: $sync.remoteRoot)
                        .onSubmit { sync.saveSettings(password: nil) }
                }
                fieldRow(title: L10n.text("webdav.sync_name")) {
                    TextField(ConfigSyncController.defaultSyncName, text: $sync.syncName)
                        .onSubmit { sync.saveSettings(password: nil) }
                }

                Toggle(isOn: Binding(
                    get: { sync.autoSyncEnabled },
                    set: { sync.setAutoSync($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("webdav.auto_sync"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DashboardTheme.text)
                        Text(L10n.text("webdav.auto_sync_hint"))
                            .font(.system(size: 10))
                            .foregroundStyle(DashboardTheme.mutedText)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider().overlay(DashboardSurface.border)

                HStack(spacing: 10) {
                    Button(L10n.text("webdav.test_connection")) {
                        sync.saveSettings(password: passwordDraft)
                        Task { await sync.testConnection() }
                    }
                    .disabled(sync.isBusy)

                    Spacer()

                    Button(L10n.text("webdav.upload")) {
                        sync.saveSettings(password: passwordDraft)
                        Task { await sync.upload(accountsStore: store.providerAccountsStore) }
                    }
                    .disabled(sync.isBusy || !sync.isConfigured)
                    .usageDockActionButtonStyle()

                    Button(L10n.text("webdav.download")) {
                        sync.saveSettings(password: passwordDraft)
                        Task {
                            if let payload = await sync.download() {
                                pendingImport = payload
                            }
                        }
                    }
                    .disabled(sync.isBusy || !sync.isConfigured)
                }
                .font(.system(size: 12, weight: .medium))

                HStack(spacing: 14) {
                    if let status = sync.statusMessage {
                        Text(status)
                            .font(.system(size: 10))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let uploaded = sync.lastUploadAt {
                        Text(L10n.format("webdav.last_upload", uploaded.formatted(date: .abbreviated, time: .shortened)))
                            .font(.system(size: 10))
                            .foregroundStyle(DashboardTheme.mutedText)
                    }
                }
            }
        }
        .onAppear {
            if passwordDraft.isEmpty, let stored = sync.storedPassword {
                passwordDraft = stored
            }
        }
        .alert(L10n.text("webdav.import_confirm_title"), isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )) {
            Button(L10n.text("webdav.import_confirm_apply")) {
                if let payload = pendingImport {
                    sync.confirmImport(payload, using: store.providerAccountsStore)
                    pendingImport = nil
                    Task { await store.refresh(forceCCUsage: true, forceClaude: true) }
                }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {
                pendingImport = nil
            }
        } message: {
            if let payload = pendingImport {
                Text(L10n.format(
                    "webdav.import_confirm_message",
                    payload.sourceDevice,
                    payload.exportedAt.formatted(date: .abbreviated, time: .shortened),
                    payload.accountCount,
                    payload.secretCount
                ))
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(DashboardTheme.secondaryText)
                .frame(width: 72, alignment: .leading)
            content()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
}
