import Foundation

/// Public, credential-free entry point for the server-curated broadcast feed.
///
/// Fork note: the upstream production server (`https://api.tokenremain.com`)
/// and the Info.plist-injected `TokenRemainBroadcastBaseURL` were removed, so
/// a personal build never contacts the original author's server. The AI feed
/// and push registration stay disabled unless `TOKENREMAIN_BROADCAST_BASE_URL`
/// is set explicitly in the environment.
enum FeedConfiguration {
    static let pollingIntervalSeconds: TimeInterval = 600

    static var baseURL: URL? {
        guard let rawValue = ProcessInfo.processInfo.environment[
            "TOKENREMAIN_BROADCAST_BASE_URL"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil
        else {
            return nil
        }
        return url
    }

    static var feedEndpoint: URL? {
        baseURL?.appending(path: "v1/ai-feed")
    }

    static var deviceRegistrationEndpoint: URL? {
        baseURL?.appending(path: "v1/devices/register")
    }

    static var sourceTitle: String {
        L10n.text("feed.source.curated")
    }
}
