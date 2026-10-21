import Foundation

/// One-time migration from the upstream `com.jamesli.usagedock` namespace to
/// this fork's `com.jingsan0801.mytokenremain` namespace.
///
/// Defaults and the provider-account data directory move automatically.
/// Keychain items intentionally do not: their ACLs are bound to the old bundle
/// identifier, so the renamed app cannot read them without a user prompt. The
/// WebDAV payload is the recovery path — re-enter the WebDAV app password once
/// and download the configuration to restore provider credentials.
@MainActor
enum LegacyNamespaceMigration {
    static let markerKey = "tokenRemain.migratedToMyTokenRemain.v1"
    static let oldDevelopmentDomain = "com.jamesli.usagedock.dev"
    static let oldProductionDomain = "com.jamesli.usagedock"
    static let oldSupportFolder = "com.jamesli.usagedock"
    static let newSupportFolder = "com.jingsan0801.mytokenremain"
    static let profilesKey = "tokenRemain.providerAccounts.v1"

    static func oldDomain(for bundleIdentifier: String?) -> String {
        bundleIdentifier?.hasSuffix(".dev") == true
            ? oldDevelopmentDomain
            : oldProductionDomain
    }

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default,
        oldDomain overrideOldDomain: String? = nil,
        oldFolderName: String = oldSupportFolder,
        newFolderName: String = newSupportFolder,
        markerKey: String = LegacyNamespaceMigration.markerKey
    ) {
        guard !defaults.bool(forKey: markerKey) else { return }

        let oldDomain = overrideOldDomain ?? oldDomain(for: bundleIdentifier)
        if oldDomain != bundleIdentifier,
           let oldDefaults = UserDefaults(suiteName: oldDomain),
           let domain = oldDefaults.persistentDomain(forName: oldDomain) {
            for (key, value) in domain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let root = supportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDirectory = root.appending(path: oldFolderName, directoryHint: .isDirectory)
        let newDirectory = root.appending(path: newFolderName, directoryHint: .isDirectory)
        var didMoveDirectory = false
        if fileManager.fileExists(atPath: oldDirectory.path),
           !fileManager.fileExists(atPath: newDirectory.path) {
            do {
                try fileManager.moveItem(at: oldDirectory, to: newDirectory)
                didMoveDirectory = true
            } catch {
                // A failed move must not block launch; the store recreates its
                // own directory and only legacy isolated-CLI accounts depend on
                // the old location.
            }
        }

        if didMoveDirectory {
            rewriteProfileDirectories(
                in: defaults,
                oldPrefix: oldDirectory.path,
                newPrefix: newDirectory.path
            )
        }

        defaults.set(true, forKey: markerKey)
    }

    /// Managed profiles persist absolute configuration directories for the
    /// isolated-CLI account kind. After moving the container, those paths must
    /// follow or the accounts would look missing.
    static func rewriteProfileDirectories(
        in defaults: UserDefaults,
        oldPrefix: String,
        newPrefix: String
    ) {
        guard let data = defaults.data(forKey: profilesKey),
              var profiles = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        var changed = false
        for index in profiles.indices {
            guard let path = profiles[index]["configurationDirectory"] as? String,
                  path.hasPrefix(oldPrefix + "/") else { continue }
            profiles[index]["configurationDirectory"] = newPrefix + path.dropFirst(oldPrefix.count)
            changed = true
        }
        guard changed,
              let updated = try? JSONSerialization.data(withJSONObject: profiles)
        else { return }
        defaults.set(updated, forKey: profilesKey)
    }
}
