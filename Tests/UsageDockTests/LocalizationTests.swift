import Foundation
import Testing
@testable import UsageDock

@Suite("Localization")
struct LocalizationTests {
    private let locales = ["en", "zh-Hans"]

    private let requiredKeys = [
        "widget.local_usage",
        "widget.ai_feed",
        "nav.overview",
        "nav.limits",
        "nav.data_sources",
        "nav.settings",
        "section.overview.subtitle",
        "risk.headline.low",
        "duration.days_hours_minutes",
        "duration.hours_minutes",
        "reset.countdown",
        "freshness.minutes",
        "quota.remaining",
        "widget.all_visible",
        "widget.add_named",
        "widget.keep_expanded",
        "widget.stop_keep_expanded",
        "widget.collapse",
        "widget.expand",
        "widget.move_up",
        "widget.move_down",
        "widget.remove_named",
        "widget.drag_help",
        "widget.drag_accessibility",
        "action.add_widget",
        "action.refresh_quota",
        "action.refresh_usage",
        "action.open_dashboard",
        "action.open_dashboard_help",
        "action.launch_at_login",
        "action.open_dashboard_settings",
        "action.restart_app",
        "action.settings",
        "action.quit",
        "action.quit_app",
        "quota.loading_official",
        "service.antigravity.running_no_quota",
        "service.antigravity.not_logged_in",
        "feed.updating",
        "feed.item_count",
        "feed.filtering",
        "feed.full_top_stories",
        "feed.important_updates",
        "feed.view_all",
        "feed.open_x_hint"
    ]

    @Test("Every supported locale contains the product-critical UI keys")
    func everyLocaleContainsCoreKeys() throws {
        for locale in locales {
            let strings = try loadStrings(locale: locale)
            for key in requiredKeys {
                let value = strings[key]
                #expect(value != nil, "Missing \(key) in \(locale)")
                #expect(value?.isEmpty == false, "Empty \(key) in \(locale)")
                #expect(value != key, "Untranslated \(key) in \(locale)")
            }
        }
    }

    /// The shipped languages. Every key in the English catalog must exist in
    /// Chinese — new UI strings cannot ship English-only there.
    private let fullyLocalizedLocales = ["zh-Hans"]

    @Test("Fully localized locales cover the entire English catalog")
    func fullyLocalizedLocalesCoverAllKeys() throws {
        let english = try loadStrings(locale: "en")
        for locale in fullyLocalizedLocales {
            let strings = try loadStrings(locale: locale)
            let missing = Set(english.keys).subtracting(strings.keys)
            #expect(
                missing.isEmpty,
                "\(locale) is missing \(missing.count) keys, e.g. \(missing.sorted().prefix(8))"
            )
            for (key, value) in strings {
                #expect(!value.isEmpty, "Empty \(key) in \(locale)")
            }
            for key in english.keys {
                #expect(
                    placeholders(in: strings[key] ?? "").sorted()
                        == placeholders(in: english[key] ?? "").sorted(),
                    "Placeholder mismatch for \(key) in \(locale)"
                )
            }
        }
    }

    @Test("Chinese ships a real localization")
    func chineseIsNotAnEnglishFallback() throws {
        let strings = try loadStrings(locale: "zh-Hans")
        #expect(strings["widget.local_usage"] == "今日本地统计")
        #expect(strings["nav.settings"] == "设置")
        #expect(strings["action.open_dashboard"] == "打开 Dashboard")
    }

    @Test("Format placeholders stay compatible in every locale")
    func formatPlaceholdersMatchEnglish() throws {
        let english = try loadStrings(locale: "en")
        for locale in locales where locale != "en" {
            let strings = try loadStrings(locale: locale)
            for key in requiredKeys {
                #expect(
                    placeholders(in: strings[key] ?? "").sorted()
                        == placeholders(in: english[key] ?? "").sorted(),
                    "Placeholder mismatch for \(key) in \(locale)"
                )
            }
        }
    }

    @Test("USD values use the requested locale")
    func currencyUsesLocale() {
        let english = L10n.usd(188.99, locale: Locale(identifier: "en_US"))
        let german = L10n.usd(188.99, locale: Locale(identifier: "de_DE"))
        #expect(english.contains("188.99"))
        #expect(german.contains("188,99"))
    }

    private func loadStrings(locale: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Sources/UsageDock/Localization")
            .appendingPathComponent("\(locale).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:\.\d+)?(?:@|lld|d|f)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
}
