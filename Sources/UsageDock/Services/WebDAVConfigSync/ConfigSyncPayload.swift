import Foundation

/// WebDAV 配置同步的载荷格式。Fork 自有功能:按用户明确选择,账号配置与
/// 手动粘贴的凭证以明文 JSON 上传到用户自己的 WebDAV 服务(HTTPS 传输)。
/// 凭证只进入这一个格式,不经过任何其他链路;不上传环境变量与 CLI 配置
/// 文件来源的密钥——那些不属于「本 App 持有的配置」。
struct ConfigSyncPayload: Codable, Sendable {
    static let currentFormat = "tokenremain-config-sync"
    /// v2 adds `trackedProviders.disabledSystemSources`. The field is optional
    /// so v1 payloads still import; a v1-only client rejects v2 rather than
    /// silently resurrecting a source the user parked.
    static let currentFormatVersion = 2

    var format: String = Self.currentFormat
    var formatVersion: Int = Self.currentFormatVersion
    var exportedAt: Date
    var sourceDevice: String

    var trackedProviders: TrackedState
    var accounts: AccountsState
    var secrets: SecretsState

    struct TrackedState: Codable, Sendable, Equatable {
        var enabled: [String]
        var order: [String]
        var hiddenFromManagement: [String]
        /// nil = v1 payload (every default source was still enabled).
        var disabledSystemSources: [String]? = nil
    }

    struct AccountsState: Codable, Sendable, Equatable {
        /// 仅 keychainSecret 型受管账号。isolatedCLI 账号(Claude/Codex 附加
        /// 账号)的凭证在 provider 自己的隔离目录里,跨机无意义,不进同步。
        var managedProfiles: [SyncedProfile]
        /// provider rawValue → "all" 或账号 id("managed.<uuid>")
        var selections: [String: String]

        struct SyncedProfile: Codable, Sendable, Equatable {
            var id: String
            var provider: String
            var displayName: String
            var isEnabled: Bool
            var createdAt: Date
        }
    }

    struct SecretsState: Codable, Sendable, Equatable {
        /// provider rawValue → 钥匙串中本 App 持有的密钥/Cookie。
        var providerSecrets: [String: String]
        var openRouterKey: String?
        var zaiKey: String?
        /// 受管账号 id → 凭证(provider 由 accounts.managedProfiles 携带)。
        var accountSecrets: [String: String]
    }

    /// 自动上传去重指纹:只覆盖内容字段,排除导出时间与来源设备。
    struct Fingerprint: Codable, Sendable {
        var trackedProviders: TrackedState
        var accounts: AccountsState
        var secrets: SecretsState
    }

    var fingerprint: Fingerprint {
        Fingerprint(trackedProviders: trackedProviders, accounts: accounts, secrets: secrets)
    }

    var accountCount: Int { accounts.managedProfiles.count }
    var secretCount: Int {
        secrets.providerSecrets.count
            + secrets.accountSecrets.count
            + (secrets.openRouterKey == nil ? 0 : 1)
            + (secrets.zaiKey == nil ? 0 : 1)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decoded(from data: Data) throws -> ConfigSyncPayload {
        let payload = try decoder().decode(ConfigSyncPayload.self, from: data)
        guard payload.format == currentFormat else {
            throw SyncFormatError.unrecognizedFormat
        }
        guard payload.formatVersion <= currentFormatVersion else {
            throw SyncFormatError.unsupportedVersion(payload.formatVersion)
        }
        return payload
    }

    enum SyncFormatError: LocalizedError {
        case unrecognizedFormat
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat:
                return L10n.text("webdav.error.bad_format")
            case .unsupportedVersion(let version):
                return L10n.format("webdav.error.newer_version", version)
            }
        }
    }
}
