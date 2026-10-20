import Foundation
import Testing
@testable import UsageDock

@Suite("WebDAV config sync")
struct WebDAVConfigSyncTests {
    private func samplePayload() -> ConfigSyncPayload {
        ConfigSyncPayload(
            exportedAt: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDevice: "Test Mac",
            trackedProviders: .init(
                enabled: ["Claude Code", "Codex"],
                order: ["Claude Code", "Codex", "Cursor"],
                hiddenFromManagement: []
            ),
            accounts: .init(
                managedProfiles: [
                    .init(
                        id: "managed.00000000-0000-0000-0000-000000000001",
                        provider: "Kimi",
                        displayName: "工作号",
                        isEnabled: true,
                        createdAt: Date(timeIntervalSince1970: 1_760_000_000)
                    )
                ],
                selections: ["Kimi": "managed.00000000-0000-0000-0000-000000000001"]
            ),
            secrets: .init(
                providerSecrets: ["DeepSeek": "sk-test"],
                openRouterKey: "sk-or-test",
                zaiKey: nil,
                accountSecrets: ["managed.00000000-0000-0000-0000-000000000001": "kimi-secret"]
            )
        )
    }

    @Test("Payload round-trips through the wire format")
    func roundTrip() throws {
        let payload = samplePayload()
        let decoded = try ConfigSyncPayload.decoded(from: payload.encoded())
        #expect(decoded.format == ConfigSyncPayload.currentFormat)
        #expect(decoded.sourceDevice == "Test Mac")
        #expect(decoded.trackedProviders.enabled == ["Claude Code", "Codex"])
        #expect(decoded.accounts.managedProfiles.first?.displayName == "工作号")
        #expect(decoded.secrets.providerSecrets["DeepSeek"] == "sk-test")
        #expect(decoded.accountCount == 1)
        #expect(decoded.secretCount == 3)
    }

    @Test("Foreign payloads and newer versions are rejected")
    func formatValidation() {
        var foreign = samplePayload()
        foreign.format = "other-app-config"
        #expect(throws: ConfigSyncPayload.SyncFormatError.self) {
            _ = try ConfigSyncPayload.decoded(from: foreign.encoded())
        }
        var payload = samplePayload()
        payload.formatVersion = ConfigSyncPayload.currentFormatVersion + 1
        #expect(throws: ConfigSyncPayload.SyncFormatError.self) {
            _ = try ConfigSyncPayload.decoded(from: payload.encoded())
        }
    }

    @Test("WebDAV client refuses non-HTTPS endpoints and unsafe path segments")
    func clientGuards() throws {
        #expect(throws: WebDAVClient.ClientError.self) {
            _ = try WebDAVClient(baseURL: URL(string: "http://dav.example.com/")!, account: "a", password: "b")
        }
        let client = try WebDAVClient(
            baseURL: URL(string: "https://dav.jianguoyun.com/dav/")!,
            account: "a",
            password: "b"
        )
        let url = try client.resourceURL(["tokenremain-sync", "default", "config.json"])
        #expect(url.absoluteString == "https://dav.jianguoyun.com/dav/tokenremain-sync/default/config.json")
        #expect(throws: WebDAVClient.ClientError.self) {
            _ = try client.resourceURL([".."])
        }
        #expect(throws: WebDAVClient.ClientError.self) {
            _ = try client.resourceURL(["a/b"])
        }
    }

    @MainActor
    @Test("Environment-sourced provider keys are exported")
    func exportsEnvironmentKeys() {
        let defaults = UserDefaults(suiteName: "WebDAVConfigSyncTests.\(UUID().uuidString)")!
        let accountsStore = ProviderAccountsStore(
            defaults: defaults,
            rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: UUID().uuidString, directoryHint: .isDirectory),
            deleteSecret: { _ in }
        )
        let controller = ConfigSyncController(defaults: defaults, observesActivation: false)
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let payload = controller.collectPayload(
            accountsStore: accountsStore,
            environment: [
                "DEEPSEEK_API_KEY": "sk-env-deepseek",
                "OPENROUTER_API_KEY": "sk-or-env",
            ],
            homeDirectory: home
        )

        #expect(payload.secrets.providerSecrets["DeepSeek"] == "sk-env-deepseek")
        #expect(payload.secrets.openRouterKey == "sk-or-env")
        #expect(payload.secrets.zaiKey == nil)
        #expect(payload.secrets.providerSecrets.count == 1)
        #expect(payload.secretCount == 2)
        #expect(payload.accountCount == 0)
    }

    @MainActor
    @Test("Import applies profiles and selections to a fresh store")
    func importAppliesToStore() {
        let defaults = UserDefaults(suiteName: "WebDAVConfigSyncTests.\(UUID().uuidString)")!
        let accountsStore = ProviderAccountsStore(
            defaults: defaults,
            rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: UUID().uuidString, directoryHint: .isDirectory),
            deleteSecret: { _ in }
        )
        let controller = ConfigSyncController(defaults: defaults, observesActivation: false)
        // Never let a test write fabricated values into the real Keychain.
        var written: [String] = []
        controller.secretWriter = .init(
            providerSecret: { provider, _ in written.append("provider:\(provider.rawValue)") },
            openRouterKey: { _ in written.append("openrouter") },
            zaiKey: { _ in written.append("zai") },
            accountSecret: { _, id, _ in written.append("account:\(id.rawValue)") }
        )
        let summary = controller.apply(samplePayload(), using: accountsStore)

        #expect(summary.profilesAdded == 1)
        #expect(summary.secretsApplied == 3)
        #expect(Set(written) == ["provider:DeepSeek", "openrouter", "account:managed.00000000-0000-0000-0000-000000000001"])
        let profile = accountsStore.profiles.first
        #expect(profile?.displayName == "工作号")
        #expect(profile?.provider.rawValue == "Kimi")
        #expect(profile?.configurationDirectory == nil)

        // 再次导入同一份载荷:更新而不是重复添加。
        let second = controller.apply(samplePayload(), using: accountsStore)
        #expect(second.profilesAdded == 0)
        #expect(second.profilesUpdated == 1)
        #expect(accountsStore.profiles.count == 1)
    }
}
