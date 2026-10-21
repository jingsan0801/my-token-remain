import Foundation

enum TokenRemainLogoState: String, CaseIterable {
    case excitedStars = "100-excited-stars"
    case happyCarets = "90-happy-carets"
    case sparkle = "80-sparkle"
    case calmDots = "70-calm-dots"
    case focusedBars = "60-focused-bars"
    case neutralDashes = "50-neutral-dashes"
    case worriedSlants = "40-worried-slants"
    case tenseChevrons = "30-tense-chevrons"
    case dizzySpirals = "20-dizzy-spirals"
    case cryingWarning = "10-crying-warning"
    case offline = "0-offline-x"

    static func resolve(remainingPercent: Double?) -> Self {
        guard let remainingPercent else { return .neutralDashes }
        switch min(max(remainingPercent, 0), 100) {
        case 96...: return .excitedStars
        case 86...: return .happyCarets
        case 76...: return .sparkle
        case 66...: return .calmDots
        case 56...: return .focusedBars
        case 46...: return .neutralDashes
        case 36...: return .worriedSlants
        case 26...: return .tenseChevrons
        case 16...: return .dizzySpirals
        case 0.5...: return .cryingWarning
        default: return .offline
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .excitedStars: return L10n.text("logo.state.excited_stars")
        case .happyCarets: return L10n.text("logo.state.happy_carets")
        case .sparkle: return L10n.text("logo.state.sparkle")
        case .calmDots: return L10n.text("logo.state.calm_dots")
        case .focusedBars: return L10n.text("logo.state.focused_bars")
        case .neutralDashes: return L10n.text("logo.state.neutral_dashes")
        case .worriedSlants: return L10n.text("logo.state.worried_slants")
        case .tenseChevrons: return L10n.text("logo.state.tense_chevrons")
        case .dizzySpirals: return L10n.text("logo.state.dizzy_spirals")
        case .cryingWarning: return L10n.text("logo.state.crying_warning")
        case .offline: return L10n.text("logo.state.offline")
        }
    }
}

enum TokenRemainLogoMeter {
    static let segmentCount = 10

    static func filledSegments(remainingPercent: Double?) -> Int? {
        guard let remainingPercent else { return nil }
        let clamped = min(max(remainingPercent, 0), 100)
        return Int((clamped / 100 * Double(segmentCount)).rounded())
    }
}
