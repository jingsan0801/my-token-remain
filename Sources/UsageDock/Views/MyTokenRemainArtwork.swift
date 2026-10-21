import AppKit

/// Dynamic brand artwork for the running Dock icon and the Settings preview.
/// The teal countdown ring encodes the lowest selected provider's remaining
/// percentage; the two meter rows keep each provider's own color and value.
enum MyTokenRemainArtwork {
    /// One meter on the tile: which provider it belongs to and how much of the
    /// headline window is left. A slot without data draws no row.
    struct Slot: Equatable {
        let provider: ProviderQuota.Provider
        let remainingPercent: Double?
    }

    private struct MeterRow {
        let remainingPercent: Double
        let color: NSColor
    }

    enum Style: String {
        /// Transparent around the mark, for in-app brand presentations.
        case bare
        /// The running Dock icon. macOS 26+ draws the bundled Icon Composer
        /// icon on the system shape but shows `applicationIconImage` exactly as
        /// given, so the runtime image must draw the navy tile itself.
        case dockTile
    }

    /// The Icon Composer fill of `Resources/AppIcon.icon`. A test keeps the
    /// runtime tile and the compiled icon in step.
    static let dockTileFill = (red: 8.0 / 255, green: 20.0 / 255, blue: 49.0 / 255)
    /// Apple's macOS icon grid: an 824-point shape centred on a 1024 canvas.
    static let dockTileInset: CGFloat = 100.0 / 1024
    static let dockTileCornerRadius: CGFloat = 185.4 / 1024

    private static let teal = NSColor(
        srgbRed: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255, alpha: 1
    )
    private static let track = NSColor(
        srgbRed: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255, alpha: 0.16
    )
    private static let meterTrack = NSColor(
        srgbRed: 29.0 / 255, green: 38.0 / 255, blue: 61.0 / 255, alpha: 0.96
    )
    private static let meterBorder = NSColor(
        srgbRed: 69.0 / 255, green: 82.0 / 255, blue: 116.0 / 255, alpha: 0.9
    )
    private static let claudeColor = NSColor(
        srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1
    )
    private static let codexColor = NSColor(
        srgbRed: 75.0 / 255, green: 156.0 / 255, blue: 251.0 / 255, alpha: 1
    )

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // The arc is continuous, so keys include the remaining percentage.
        // A slightly larger cache still keeps the working set tiny.
        cache.countLimit = 24
        return cache
    }()

    /// Claude and Codex keep the meter colors the product shipped with; every
    /// other provider uses its stable theme accent.
    static func meterColor(for provider: ProviderQuota.Provider) -> NSColor {
        switch provider {
        case .claude: return claudeColor
        case .codex: return codexColor
        default: return NSColor(DashboardTheme.accent(for: provider))
        }
    }

    /// The historical pairing, kept for callers that still think in it.
    static func slots(claudeRemaining: Double?, codexRemaining: Double?) -> [Slot] {
        [
            Slot(provider: .claude, remainingPercent: claudeRemaining),
            Slot(provider: .codex, remainingPercent: codexRemaining)
        ]
    }

    /// The ring follows whichever selected provider is lowest.
    static func moodRemaining(_ slots: [Slot]) -> Double? {
        slots.compactMap(\.remainingPercent).min()
    }

    static func renderKey(claudeRemaining: Double?, codexRemaining: Double?) -> String {
        renderKey(slots: slots(claudeRemaining: claudeRemaining, codexRemaining: codexRemaining))
    }

    /// Stable identity of the artwork for a set of slots. Two equal keys always
    /// render pixel-identical images, so callers can skip redundant dock redraws.
    static func renderKey(slots: [Slot]) -> String {
        let state = TokenRemainLogoState.resolve(remainingPercent: moodRemaining(slots))
        let levels = slots.map { slot -> String in
            guard let remaining = slot.remainingPercent else {
                return "\(slot.provider.rawValue)_"
            }
            let filled = TokenRemainLogoMeter.filledSegments(remainingPercent: remaining) ?? -1
            return "\(slot.provider.rawValue)\(filled)@\(String(format: "%.1f", remaining))"
        }
        return (["ring", state.rawValue] + levels).joined(separator: "-")
    }

    static func image(
        claudeRemaining: Double?,
        codexRemaining: Double?,
        size: CGFloat = 1024
    ) -> NSImage {
        image(
            slots: slots(claudeRemaining: claudeRemaining, codexRemaining: codexRemaining),
            size: size
        )
    }

    static func image(slots: [Slot], size: CGFloat = 1024, style: Style = .bare) -> NSImage {
        let key = renderKey(slots: slots)
        let cacheKey = "\(key)-\(style.rawValue)-\(Int(size.rounded()))" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let graphics = NSGraphicsContext.current else { return false }
            graphics.shouldAntialias = true
            graphics.imageInterpolation = .high
            let side = min(rect.width, rect.height)

            let canvas: NSRect
            switch style {
            case .bare:
                canvas = rect
            case .dockTile:
                let body = rect.insetBy(
                    dx: size * dockTileInset,
                    dy: size * dockTileInset
                )
                let shape = NSBezierPath(
                    roundedRect: body,
                    xRadius: size * dockTileCornerRadius,
                    yRadius: size * dockTileCornerRadius
                )
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                NSColor(
                    srgbRed: dockTileFill.red,
                    green: dockTileFill.green,
                    blue: dockTileFill.blue,
                    alpha: 1
                ).setFill()
                body.fill()
                NSGraphicsContext.restoreGraphicsState()
                canvas = body
            }

            drawRing(
                in: canvas,
                remaining: moodRemaining(slots),
                side: side
            )
            drawMeters(
                slots.compactMap { slot in
                    slot.remainingPercent.map {
                        MeterRow(remainingPercent: $0, color: meterColor(for: slot.provider))
                    }
                },
                in: canvas
            )
            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func arcColor(remaining: Double?) -> NSColor {
        guard let remaining else { return teal }
        if remaining < 10 { return NSColor(DashboardTheme.danger) }
        if remaining < 30 { return NSColor(DashboardTheme.warning) }
        return teal
    }

    private static func drawRing(in rect: NSRect, remaining: Double?, side: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY + side * 0.02)
        let radius = side * 0.27

        var ticks = NSBezierPath()
        for index in 0..<12 {
            // Keep the bottom half — and the bottom tick in particular —
            // clear for the provider meters.
            guard index != 0, index <= 3 || index >= 9 else { continue }
            let angle = (-90 + Double(index) * 30) * Double.pi / 180
            let inner = radius * 1.23
            let outer = radius * 1.43
            ticks.move(to: CGPoint(
                x: center.x + cos(angle) * inner,
                y: center.y + sin(angle) * inner
            ))
            ticks.line(to: CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            ))
        }
        teal.withAlphaComponent(0.22).setStroke()
        ticks.lineWidth = side * 0.025
        ticks.lineCapStyle = .round
        ticks.stroke()

        let trackPath = NSBezierPath()
        trackPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: -90,
            endAngle: 270,
            clockwise: false
        )
        track.setStroke()
        trackPath.lineWidth = side * 0.06
        trackPath.lineCapStyle = .round
        trackPath.stroke()

        guard let remaining else { return }
        let clamped = min(max(remaining, 0), 100)
        guard clamped > 0 else { return }
        let endAngle = -90 + 3.6 * clamped
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: -90,
            endAngle: endAngle,
            clockwise: false
        )
        arcColor(remaining: clamped).setStroke()
        arc.lineWidth = side * 0.06
        arc.lineCapStyle = .round
        arc.stroke()

        let radians = endAngle * Double.pi / 180
        let dotRadius = side * 0.045
        let dotCenter = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
        arcColor(remaining: clamped).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: dotCenter.x - dotRadius,
            y: dotCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )).fill()
    }

    private static func drawMeters(_ rows: [MeterRow], in rect: NSRect) {
        guard !rows.isEmpty else { return }
        let side = min(rect.width, rect.height)
        let segmentCount = 10
        let meterWidth = side * 0.63
        let gap = max(1, side * 0.008)
        let segmentWidth = (meterWidth - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
        let segmentHeight = max(2, side * 0.024)
        let originX = rect.midX - meterWidth / 2
        let startFromTop = side * (rows.count == 2 ? 0.837 : 0.862)
        let startY = rect.maxY - startFromTop - segmentHeight
        let rowGap = side * 0.049

        for (rowIndex, row) in rows.enumerated() {
            let filled = TokenRemainLogoMeter.filledSegments(
                remainingPercent: row.remainingPercent
            ) ?? 0
            let y = startY - CGFloat(rowIndex) * rowGap
            for segment in 0..<segmentCount {
                let segmentRect = NSRect(
                    x: originX + CGFloat(segment) * (segmentWidth + gap),
                    y: y,
                    width: segmentWidth,
                    height: segmentHeight
                )
                let path = NSBezierPath(
                    roundedRect: segmentRect,
                    xRadius: max(0.75, segmentHeight * 0.16),
                    yRadius: max(0.75, segmentHeight * 0.16)
                )
                (segment < filled ? row.color : meterTrack).setFill()
                path.fill()
                meterBorder.setStroke()
                path.lineWidth = max(0.5, side * 0.0015)
                path.stroke()
            }
        }
    }
}
