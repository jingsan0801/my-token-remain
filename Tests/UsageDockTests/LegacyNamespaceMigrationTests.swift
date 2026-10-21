import Foundation
import Testing
@testable import UsageDock

@MainActor
@Suite("Legacy namespace migration")
struct LegacyNamespaceMigrationTests {
    @Test("Development and production builds migrate from their matching old domain")
    func oldDomainSelection() {
        #expect(
            LegacyNamespaceMigration.oldDomain(for: "com.jingsan0801.mytokenremain.dev")
                == "com.jamesli.usagedock.dev"
        )
        #expect(
            LegacyNamespaceMigration.oldDomain(for: "com.jingsan0801.mytokenremain")
                == "com.jamesli.usagedock"
        )
    }

    @Test("Defaults, account directories and profile paths move once")
    func migratesDefaultsAndDirectories() throws {
        let suffix = UUID().uuidString
        let oldDomain = "migration-test-old-\(suffix)"
        let newSuite = "migration-test-new-\(suffix)"
        let oldDefaults = UserDefaults(suiteName: oldDomain)!
        let newDefaults = UserDefaults(suiteName: newSuite)!
        defer {
            oldDefaults.removePersistentDomain(forName: oldDomain)
            newDefaults.removePersistentDomain(forName: newSuite)
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "migration-test-\(suffix)", directoryHint: .isDirectory)
        let oldFolder = root.appending(path: "old-support", directoryHint: .isDirectory)
        let newFolder = root.appending(path: "new-support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: oldFolder.appending(path: "provider-accounts", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        oldDefaults.set("dark", forKey: "theme")
        let profile = [[
            "id": "managed.00000000-0000-0000-0000-000000000001",
            "provider": "Codex",
            "displayName": "Work",
            "kind": "managed",
            "configurationDirectory": oldFolder
                .appending(path: "provider-accounts/work").path,
            "isEnabled": true,
            "createdAt": 0
        ]]
        oldDefaults.set(
            try JSONSerialization.data(withJSONObject: profile),
            forKey: LegacyNamespaceMigration.profilesKey
        )

        LegacyNamespaceMigration.runIfNeeded(
            defaults: newDefaults,
            supportDirectory: root,
            oldDomain: oldDomain,
            oldFolderName: "old-support",
            newFolderName: "new-support",
            markerKey: "migration-test-marker-\(suffix)"
        )

        #expect(newDefaults.string(forKey: "theme") == "dark")
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
        let data = try #require(newDefaults.data(forKey: LegacyNamespaceMigration.profilesKey))
        let profiles = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        #expect(
            profiles.first?["configurationDirectory"] as? String
                == newFolder.appending(path: "provider-accounts/work").path
        )
        #expect(newDefaults.bool(forKey: "migration-test-marker-\(suffix)"))

        // A second launch must not copy stale values over newer local edits.
        oldDefaults.set("light", forKey: "theme")
        LegacyNamespaceMigration.runIfNeeded(
            defaults: newDefaults,
            supportDirectory: root,
            oldDomain: oldDomain,
            oldFolderName: "old-support",
            newFolderName: "new-support",
            markerKey: "migration-test-marker-\(suffix)"
        )
        #expect(newDefaults.string(forKey: "theme") == "dark")
    }
}
