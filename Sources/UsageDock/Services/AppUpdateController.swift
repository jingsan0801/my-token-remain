import Combine
import Foundation

/// Pure scheduling rules for remote update discovery.
///
/// Background probes only fetch and validate the signed appcast. They never
/// download an installer, so a discovered release cannot become a stale
/// resumable update that prevents Sparkle from seeing a newer release later.
struct AppUpdateCheckPolicy {
    static let noUpdateInterval: TimeInterval = 6 * 60 * 60
    static let updateAvailableInterval: TimeInterval = 12 * 60 * 60
    static let busyRetryInterval: TimeInterval = 15 * 60

    static func nextDelay(
        hasAvailableUpdate: Bool,
        consecutiveFailures: Int
    ) -> TimeInterval {
        switch consecutiveFailures {
        case ...0:
            return hasAvailableUpdate ? updateAvailableInterval : noUpdateInterval
        case 1:
            return 60 * 60
        case 2:
            return 3 * 60 * 60
        default:
            return 6 * 60 * 60
        }
    }

    static func initialDelay(
        now: Date,
        lastCheckDate: Date?,
        hasAvailableUpdate: Bool
    ) -> TimeInterval {
        guard let lastCheckDate,
              lastCheckDate <= now else { return 0 }
        let interval = nextDelay(
            hasAvailableUpdate: hasAvailableUpdate,
            consecutiveFailures: 0
        )
        return max(0, interval - now.timeIntervalSince(lastCheckDate))
    }

    static func isNewerBuild(_ candidate: String, than current: String) -> Bool {
        guard let candidateComponents = buildComponents(candidate),
              let currentComponents = buildComponents(current) else { return false }
        let count = max(candidateComponents.count, currentComponents.count)
        for index in 0..<count {
            let candidatePart = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentPart = index < currentComponents.count ? currentComponents[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func buildComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let components = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        return components.count == parts.count ? components : nil
    }
}

/// Fork note: this personal build removes the Sparkle auto-update path. The
/// upstream feed pointed at the original author's GitHub releases and its
/// EdDSA key, so an "update" would have replaced this self-built app with
/// their signed binaries. This stub keeps the call sites compiling and never
/// starts an updater; `availableVersion` stays nil so the dashboard update
/// banner never appears. Sparkle is not a dependency of this fork anymore.
@MainActor
final class AppUpdateController: ObservableObject {
    static let shared = AppUpdateController()

    @Published private(set) var availableVersion: String?

    private init() {
        availableVersion = nil
    }

    func start() {}

    func checkIfDue(now: Date = Date()) {}

    func presentAvailableUpdate() {}

    func configurePreview(arguments: [String]) {}
}
