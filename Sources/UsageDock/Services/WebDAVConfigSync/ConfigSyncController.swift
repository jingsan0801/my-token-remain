import AppKit
import CryptoKit
import Foundation

/// WebDAV 配置同步(账号配置 + 本 App 持有的凭证)的编排层。Fork 自有功能。
///
/// 明文上传是用户的明确选择:数据只去用户自己配置的 WebDAV 服务,HTTPS
/// 传输,应用密码存本机钥匙串(不参与 iCloud 钥匙串同步)。导出只收集
/// 钥匙串中本 App 持有的凭证;环境变量与 CLI 配置文件来源的密钥不属于
/// 本 App 的配置,不进入载荷。
@MainActor
final class ConfigSyncController: ObservableObject {
    static let shared = ConfigSyncController()

    enum DefaultsKey {
        static let serverURL = "tokenRemain.webdavSync.serverURL"
        static let account = "tokenRemain.webdavSync.account"
        static let remoteRoot = "tokenRemain.webdavSync.remoteRoot"
        static let syncName = "tokenRemain.webdavSync.syncName"
        static let autoSync = "tokenRemain.webdavSync.autoSync"
        static let lastUploadAt = "tokenRemain.webdavSync.lastUploadAt"
        static let lastDownloadAt = "tokenRemain.webdavSync.lastDownloadAt"
        static let lastUploadedFingerprint = "tokenRemain.webdavSync.lastFingerprint"
    }

    static let defaultServerURL = "https://dav.jianguoyun.com/dav/"
    static let defaultRemoteRoot = "tokenremain-sync"
    static let defaultSyncName = "default"
    static let remoteFileName = "config.json"

    @Published var serverURL: String
    @Published var account: String
    @Published var remoteRoot: String
    @Published var syncName: String
    @Published var autoSyncEnabled: Bool
    @Published private(set) var lastUploadAt: Date?
    @Published private(set) var lastDownloadAt: Date?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?

    /// 账号仓库由 App 入口注入(UsageStore 持有),避免再造第二个实例。
    var accountsStoreProvider: (() -> ProviderAccountsStore?)?

    private let defaults: UserDefaults
    private var autoSyncTask: Task<Void, Never>?
    private var becomesActiveObserver: NSObjectProtocol?

    private var passwordStore: KeychainSecretStore {
        KeychainSecretStore(
            service: AppOwnedKeychainNamespace.current.service("webdav-sync"),
            account: "app-password",
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    init(defaults: UserDefaults = .standard, observesActivation: Bool = true) {
        self.defaults = defaults
        serverURL = defaults.string(forKey: DefaultsKey.serverURL) ?? Self.defaultServerURL
        account = defaults.string(forKey: DefaultsKey.account) ?? ""
        remoteRoot = defaults.string(forKey: DefaultsKey.remoteRoot) ?? Self.defaultRemoteRoot
        syncName = defaults.string(forKey: DefaultsKey.syncName) ?? Self.defaultSyncName
        autoSyncEnabled = defaults.bool(forKey: DefaultsKey.autoSync)
        lastUploadAt = defaults.object(forKey: DefaultsKey.lastUploadAt) as? Date
        lastDownloadAt = defaults.object(forKey: DefaultsKey.lastDownloadAt) as? Date

        if observesActivation {
            becomesActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.autoUploadIfNeeded()
                }
            }
        }
    }

    deinit {
        if let becomesActiveObserver {
            NotificationCenter.default.removeObserver(becomesActiveObserver)
        }
    }

    // MARK: - 设置

    var storedPassword: String? {
        try? passwordStore.read()
    }

    var isConfigured: Bool {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https" else { return false }
        return !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && storedPassword?.isEmpty == false
    }

    func saveSettings(password: String?) {
        defaults.set(serverURL, forKey: DefaultsKey.serverURL)
        defaults.set(account, forKey: DefaultsKey.account)
        defaults.set(remoteRoot, forKey: DefaultsKey.remoteRoot)
        defaults.set(syncName, forKey: DefaultsKey.syncName)
        if let password, !password.isEmpty {
            try? passwordStore.save(password)
        }
    }

    func setAutoSync(_ enabled: Bool) {
        autoSyncEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.autoSync)
    }

    private func makeClient() throws -> WebDAVClient {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw WebDAVClient.ClientError.invalidURL
        }
        guard let password = storedPassword, !password.isEmpty else {
            throw WebDAVClient.ClientError.authRejected
        }
        return try WebDAVClient(
            baseURL: url,
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }

    private var remotePath: [String] {
        let root = remoteRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = syncName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [root.isEmpty ? Self.defaultRemoteRoot : root,
                name.isEmpty ? Self.defaultSyncName : name,
                Self.remoteFileName]
    }

    // MARK: - 导出

    func collectPayload(accountsStore: ProviderAccountsStore) -> ConfigSyncPayload {
        let tracked = TrackedProvidersStore.shared
        let trackedState = ConfigSyncPayload.TrackedState(
            enabled: tracked.enabled.map(\.rawValue).sorted(),
            order: tracked.order.map(\.rawValue),
            hiddenFromManagement: tracked.hiddenFromManagement.map(\.rawValue).sorted()
        )

        var syncedProfiles: [ConfigSyncPayload.AccountsState.SyncedProfile] = []
        var selections: [String: String] = [:]
        var accountSecrets: [String: String] = [:]

        for profile in accountsStore.profiles where profile.credentialKind == .keychainSecret {
            syncedProfiles.append(.init(
                id: profile.id.rawValue,
                provider: profile.provider.rawValue,
                displayName: profile.displayName,
                isEnabled: profile.isEnabled,
                createdAt: profile.createdAt
            ))
            if let secret = try? ProviderAccountSecretStore(provider: profile.provider, accountID: profile.id).load() {
                accountSecrets[profile.id.rawValue] = secret
            }
        }
        for (provider, selection) in accountsStore.selections {
            switch selection {
            case .all:
                selections[provider.rawValue] = "all"
            case .account(let id):
                selections[provider.rawValue] = id.rawValue
            }
        }

        var providerSecrets: [String: String] = [:]
        for descriptor in ProviderSecretStore.descriptors {
            let store = ProviderSecretStore(provider: descriptor.provider)
            if let value = try? store.loadFromKeychain(interaction: .disallowed) {
                providerSecrets[descriptor.provider.rawValue] = value
            }
        }
        let openRouterKey = try? OpenRouterKeyStore().loadFromKeychain(interaction: .disallowed)
        let zaiKey = try? ZAIKeyStore().loadFromKeychain(interaction: .disallowed)

        return ConfigSyncPayload(
            exportedAt: Date(),
            sourceDevice: Host.current().localizedName
                ?? ProcessInfo.processInfo.hostName,
            trackedProviders: trackedState,
            accounts: ConfigSyncPayload.AccountsState(
                managedProfiles: syncedProfiles,
                selections: selections
            ),
            secrets: ConfigSyncPayload.SecretsState(
                providerSecrets: providerSecrets,
                openRouterKey: openRouterKey,
                zaiKey: zaiKey,
                accountSecrets: accountSecrets
            )
        )
    }

    // MARK: - 导入

    struct ImportSummary: Sendable {
        var profilesAdded = 0
        var profilesUpdated = 0
        var secretsApplied = 0
    }

    /// 整体应用一份远端载荷。调用前必须已经过用户确认(覆盖语义)。
    func apply(_ payload: ConfigSyncPayload, using accountsStore: ProviderAccountsStore) -> ImportSummary {
        var summary = ImportSummary()

        let tracked = TrackedProvidersStore.shared
        tracked.applySyncedState(
            enabled: Set(payload.trackedProviders.enabled.compactMap(ProviderQuota.Provider.init(rawValue:))),
            order: payload.trackedProviders.order.compactMap(ProviderQuota.Provider.init(rawValue:)),
            hiddenFromManagement: Set(payload.trackedProviders.hiddenFromManagement.compactMap(ProviderQuota.Provider.init(rawValue:)))
        )

        for synced in payload.accounts.managedProfiles {
            guard let provider = ProviderQuota.Provider(rawValue: synced.provider) else { continue }
            let id = ProviderAccountID(rawValue: synced.id)
            if accountsStore.profiles.contains(where: { $0.id == id }) {
                accountsStore.rename(id, to: synced.displayName)
                accountsStore.setEnabled(synced.isEnabled, for: id)
                summary.profilesUpdated += 1
            } else {
                let profile = ProviderAccountProfile(
                    id: id,
                    provider: provider,
                    displayName: synced.displayName,
                    kind: .managed,
                    configurationDirectory: nil,
                    isEnabled: synced.isEnabled,
                    createdAt: synced.createdAt
                )
                let before = accountsStore.profiles.count
                accountsStore.commit(profile)
                if accountsStore.profiles.count > before { summary.profilesAdded += 1 }
            }
        }

        for (providerRaw, selectionRaw) in payload.accounts.selections {
            guard let provider = ProviderQuota.Provider(rawValue: providerRaw) else { continue }
            if selectionRaw == "all" {
                accountsStore.setSelection(.all, for: provider)
            } else {
                accountsStore.setSelection(.account(ProviderAccountID(rawValue: selectionRaw)), for: provider)
            }
        }

        for (providerRaw, secret) in payload.secrets.providerSecrets {
            guard let provider = ProviderQuota.Provider(rawValue: providerRaw) else { continue }
            try? ProviderSecretStore(provider: provider).save(secret)
            summary.secretsApplied += 1
        }
        if let key = payload.secrets.openRouterKey {
            try? OpenRouterKeyStore().save(key)
            summary.secretsApplied += 1
        }
        if let key = payload.secrets.zaiKey {
            try? ZAIKeyStore().save(key)
            summary.secretsApplied += 1
        }
        for (accountIDRaw, secret) in payload.secrets.accountSecrets {
            let id = ProviderAccountID(rawValue: accountIDRaw)
            guard let profile = accountsStore.profiles.first(where: { $0.id == id }) else { continue }
            try? ProviderAccountSecretStore(provider: profile.provider, accountID: id).save(secret)
            summary.secretsApplied += 1
        }
        return summary
    }

    // MARK: - 上传 / 下载

    func upload(accountsStore: ProviderAccountsStore) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let payload = collectPayload(accountsStore: accountsStore)
            let data = try payload.encoded()
            try await makeClient().upload(data: data, remotePath: remotePath)
            let now = Date()
            lastUploadAt = now
            defaults.set(now, forKey: DefaultsKey.lastUploadAt)
            defaults.set(fingerprintString(of: payload), forKey: DefaultsKey.lastUploadedFingerprint)
            statusMessage = L10n.format("webdav.status.uploaded", now.formatted(date: .omitted, time: .shortened))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// 下载成功返回待确认的载荷,由 UI 弹确认后再调 apply。
    func download() async -> ConfigSyncPayload? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await makeClient().download(remotePath: remotePath)
            let payload = try ConfigSyncPayload.decoded(from: data)
            statusMessage = nil
            return payload
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func confirmImport(_ payload: ConfigSyncPayload, using accountsStore: ProviderAccountsStore) {
        _ = apply(payload, using: accountsStore)
        let now = Date()
        lastDownloadAt = now
        defaults.set(now, forKey: DefaultsKey.lastDownloadAt)
        defaults.set(fingerprintString(of: payload), forKey: DefaultsKey.lastUploadedFingerprint)
        statusMessage = L10n.format("webdav.status.downloaded", now.formatted(date: .omitted, time: .shortened))
    }

    func testConnection() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await makeClient().testConnection()
            statusMessage = L10n.text("webdav.status.connected")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - 自动上传

    /// App 激活时检查:配置指纹与上次上传不一致才上传,避免每次激活都打网络。
    private func autoUploadIfNeeded() {
        guard autoSyncEnabled, isConfigured, autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            defer { self?.autoSyncTask = nil }
            guard let self else { return }
            // 启动早期 App 入口尚未注入账号仓库时放弃本次,下次激活再试。
            guard let accountsStore = accountsStoreProvider?() else { return }
            let payload = collectPayload(accountsStore: accountsStore)
            let fingerprint = fingerprintString(of: payload)
            guard fingerprint != defaults.string(forKey: DefaultsKey.lastUploadedFingerprint) else { return }
            await upload(accountsStore: accountsStore)
        }
    }

    private func fingerprintString(of payload: ConfigSyncPayload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(payload.fingerprint) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
