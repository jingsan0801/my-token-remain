import AppKit
import XCTest
@testable import UsageDock

final class TokenRemainLogoTests: XCTestCase {
    func testDockRenderKeyDistinguishesProviderIdentityAndPresence() {
        // Claude 单条与 Codex 单条颜色不同,同档位也必须是不同的 key;
        // key 相同则跳过 Dock 重绘,混淆会让图标停在另一家的颜色上。
        XCTAssertNotEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: nil),
            MyTokenRemainArtwork.renderKey(claudeRemaining: nil, codexRemaining: 45)
        )
        // 双条与单条、无数据分别可区分。
        XCTAssertNotEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: 45),
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: nil)
        )
        XCTAssertNotEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: nil, codexRemaining: nil),
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: nil)
        )
        // 相同输入必须稳定,内容去重才有意义。
        XCTAssertEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: 12),
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: 12)
        )
    }

    func testDockRenderKeyFollowsTheSelectedProviderPair() {
        typealias Slot = MyTokenRemainArtwork.Slot
        // The historical convenience API is the default pair, not a separate
        // rendering path.
        XCTAssertEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: 12),
            MyTokenRemainArtwork.renderKey(slots: [
                Slot(provider: .claude, remainingPercent: 45),
                Slot(provider: .codex, remainingPercent: 12)
            ])
        )
        // Same values on a different pair, or the same pair swapped top and
        // bottom, is a different picture and must not be deduplicated away.
        let claudeCursor = MyTokenRemainArtwork.renderKey(slots: [
            Slot(provider: .claude, remainingPercent: 45),
            Slot(provider: .cursor, remainingPercent: 12)
        ])
        XCTAssertNotEqual(
            claudeCursor,
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45, codexRemaining: 12)
        )
        XCTAssertNotEqual(
            claudeCursor,
            MyTokenRemainArtwork.renderKey(slots: [
                Slot(provider: .cursor, remainingPercent: 12),
                Slot(provider: .claude, remainingPercent: 45)
            ])
        )
        XCTAssertEqual(
            MyTokenRemainArtwork.moodRemaining([
                Slot(provider: .grok, remainingPercent: nil),
                Slot(provider: .cursor, remainingPercent: 12)
            ]),
            12
        )
    }

    func testDockMeterColorsKeepClaudeAndCodexArtwork() {
        let claude = MyTokenRemainArtwork.meterColor(for: .claude).usingColorSpace(.sRGB)
        let codex = MyTokenRemainArtwork.meterColor(for: .codex).usingColorSpace(.sRGB)
        XCTAssertEqual(claude.map { Int(($0.redComponent * 255).rounded()) }, 217)
        XCTAssertEqual(codex.map { Int(($0.blueComponent * 255).rounded()) }, 251)
        XCTAssertNotNil(MyTokenRemainArtwork.meterColor(for: .cursor).usingColorSpace(.sRGB))
    }

    @MainActor
    func testHeadLogoSlotsFollowTheUsersOrderAndHeadlineWindow() {
        let cursor = ProviderQuota(
            provider: .cursor,
            primary: QuotaWindow(usedPercent: 30, windowMinutes: 43_200, resetsAt: nil),
            secondary: nil,
            planName: nil,
            capturedAt: .now
        )
        let slots = StatusBarPresentation.headLogoSlots(
            providers: [.cursor, .claude],
            strategy: .shortestWindow,
            quota: { $0 == .cursor ? cursor : nil }
        )
        XCTAssertEqual(slots, [
            MyTokenRemainArtwork.Slot(provider: .cursor, remainingPercent: 70),
            MyTokenRemainArtwork.Slot(provider: .claude, remainingPercent: nil)
        ])
    }

    func testLiveSecondCountdownOnlyInsideTheFinalHour() {
        let now = Date(timeIntervalSince1970: 1_784_966_400)
        // 已过期的重置时间必须走静态展示,不允许钉住秒级刷新。
        XCTAssertFalse(UsageFormatting.showsLiveSecondCountdown(to: now.addingTimeInterval(-5), now: now))
        XCTAssertFalse(UsageFormatting.showsLiveSecondCountdown(to: now, now: now))
        XCTAssertTrue(UsageFormatting.showsLiveSecondCountdown(to: now.addingTimeInterval(1_800), now: now))
        XCTAssertTrue(UsageFormatting.showsLiveSecondCountdown(to: now.addingTimeInterval(3_599), now: now))
        XCTAssertFalse(UsageFormatting.showsLiveSecondCountdown(to: now.addingTimeInterval(3_600), now: now))
        XCTAssertFalse(UsageFormatting.showsLiveSecondCountdown(to: now.addingTimeInterval(7_200), now: now))
    }

    func testMenuBarKeepsEveryConfiguredTrackedProviderInUserOrder() {
        let providers = StatusBarPresentation.visibleProviders(
            configured: [.claude, .codex, .cursor],
            tracked: [.claude, .codex]
        )

        XCTAssertEqual(providers, [.claude, .codex])
    }

    func testMenuBarModesKeepSelectionUnlessMinimalWasExplicitlyChosen() {
        let selected: [ProviderQuota.Provider] = [.claude, .codex]
        let remaining: [ProviderQuota.Provider: Double] = [.claude: 99, .codex: 52]

        XCTAssertEqual(
            StatusBarPresentation.displayedProviders(
                mode: .full,
                selected: selected,
                remainingPercent: remaining
            ),
            selected
        )
        XCTAssertEqual(
            StatusBarPresentation.displayedProviders(
                mode: .compact,
                selected: selected,
                remainingPercent: remaining
            ),
            selected
        )
        XCTAssertEqual(
            StatusBarPresentation.displayedProviders(
                mode: .minimal,
                selected: selected,
                remainingPercent: remaining
            ),
            [.codex]
        )
    }

    func testMenuBarSummaryDefaultsToShortestGeneralWindowAndIgnoresFableQuota() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 11, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 28, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now,
            scopedWindows: [
                ScopedQuotaWindow(
                    scopeID: "fable",
                    displayName: "Fable",
                    window: QuotaWindow(usedPercent: 88, windowMinutes: 10_080, resetsAt: nil)
                )
            ]
        )

        XCTAssertEqual(
            StatusBarPresentation.headlineRemainingPercent(in: claude),
            89
        )
        XCTAssertEqual(
            StatusBarPresentation.remainingText(for: claude),
            "89%"
        )
        XCTAssertEqual(
            StatusBarPresentation.tooltipProviderLabel(.claude, quota: claude),
            "Claude · \(UsageFormatting.windowName(minutes: 300))"
        )
        XCTAssertEqual(
            StatusBarPresentation.headlineRemainingPercent(
                in: claude,
                strategy: .lowestRemaining
            ),
            72
        )
    }

    func testMenuBarShowsMonetaryBalanceInsteadOfAvailabilityPercent() {
        let deepSeek = ProviderQuota(
            provider: .deepseek,
            primary: QuotaWindow(usedPercent: 0, windowMinutes: 0, resetsAt: nil),
            secondary: nil,
            planName: "Balance ¥90.56",
            capturedAt: .now,
            remainingBalance: QuotaBalance(amount: 90.56, currencyCode: "CNY")
        )

        XCTAssertEqual(StatusBarPresentation.headlineRemainingPercent(in: deepSeek), 100)
        XCTAssertEqual(StatusBarPresentation.remainingText(for: deepSeek), "¥90.56")
    }

    func testEmotionBandsCoverFullQuotaRange() {
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 100), .excitedStars)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 90), .happyCarets)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 80), .sparkle)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 70), .calmDots)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 60), .focusedBars)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 50), .neutralDashes)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 40), .worriedSlants)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 30), .tenseChevrons)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 20), .dizzySpirals)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 10), .cryingWarning)
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: 0), .offline)
    }

    func testUnknownQuotaUsesNeutralState() {
        XCTAssertEqual(TokenRemainLogoState.resolve(remainingPercent: nil), .neutralDashes)
    }

    func testDockLogoQuotaMeterUsesTheActualRemainingPercent() {
        XCTAssertNil(TokenRemainLogoMeter.filledSegments(remainingPercent: nil))
        XCTAssertEqual(TokenRemainLogoMeter.filledSegments(remainingPercent: 0), 0)
        XCTAssertEqual(TokenRemainLogoMeter.filledSegments(remainingPercent: 45), 5)
        XCTAssertEqual(TokenRemainLogoMeter.filledSegments(remainingPercent: 100), 10)
    }

    func testDockRenderKeyTracksContinuousArcProgress() {
        XCTAssertNotEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45.1, codexRemaining: nil),
            MyTokenRemainArtwork.renderKey(claudeRemaining: 45.2, codexRemaining: nil)
        )
        XCTAssertNotEqual(
            MyTokenRemainArtwork.renderKey(claudeRemaining: 9, codexRemaining: nil),
            MyTokenRemainArtwork.renderKey(claudeRemaining: 50, codexRemaining: nil)
        )
    }

    @MainActor
    func testDockLogoDefaultsEachProviderToItsShortestGeneralWindow() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 85, windowMinutes: 10_080, resetsAt: nil),
            planName: nil,
            capturedAt: .now
        )
        let codex = ProviderQuota(
            provider: .codex,
            primary: QuotaWindow(usedPercent: 54, windowMinutes: 10_080, resetsAt: nil),
            secondary: nil,
            planName: nil,
            capturedAt: .now
        )

        let selection = UsageStore.logoQuotaSelection(from: [claude, codex])
        XCTAssertEqual(selection?.provider, .codex)
        XCTAssertEqual(selection?.windowMinutes, 10_080)
        XCTAssertEqual(selection?.remainingPercent, 46)
        XCTAssertEqual(UsageStore.aggregateRemainingPercent(from: [claude, codex]), 46)

        let tightest = UsageStore.logoQuotaSelection(
            from: [claude, codex],
            strategy: .lowestRemaining
        )
        XCTAssertEqual(tightest?.provider, .claude)
        XCTAssertEqual(tightest?.windowMinutes, 10_080)
        XCTAssertEqual(tightest?.remainingPercent, 15)
    }

    @MainActor
    func testDockLogoUsesShortestWindowEvenWhenItIsSecondary() {
        let claude = ProviderQuota(
            provider: .claude,
            primary: QuotaWindow(usedPercent: 20, windowMinutes: 10_080, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 92, windowMinutes: 300, resetsAt: nil),
            planName: nil,
            capturedAt: .now
        )

        let selection = UsageStore.logoQuotaSelection(from: [claude])
        XCTAssertEqual(selection?.windowMinutes, 300)
        XCTAssertEqual(selection?.remainingPercent, 8)
    }

    // MARK: - macOS 26 app icon

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The bundled Icon Composer icon and the running Dock tile are drawn by
    /// different code; the same navy in both is what keeps launching the app
    /// from visibly swapping its icon.
    func testIconComposerFillMatchesTheRuntimeDockTile() throws {
        let iconURL = repositoryRoot.appending(path: "Resources/AppIcon.icon")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: iconURL.appending(path: "icon.json"))) as? [String: Any]
        )
        let fill = try XCTUnwrap((json["fill"] as? [String: Any])?["solid"] as? String)
        let components = try XCTUnwrap(fill.split(separator: ":").last)
            .split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(components.count, 4)
        let tile = MyTokenRemainArtwork.dockTileFill
        XCTAssertEqual(components[0], tile.red, accuracy: 0.002)
        XCTAssertEqual(components[1], tile.green, accuracy: 0.002)
        XCTAssertEqual(components[2], tile.blue, accuracy: 0.002)

        // Every layer must point at an image that ships in the package.
        let groups = try XCTUnwrap(json["groups"] as? [[String: Any]])
        let images = groups.flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["image-name"] as? String }
        XCTAssertFalse(images.isEmpty)
        for image in images {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: iconURL.appending(path: "Assets/\(image)").path),
                "missing AppIcon.icon asset \(image)"
            )
        }
    }

    /// macOS 26+ picks the compiled icon by name; older systems keep the
    /// full-resolution icns, which actool's own fallback icns would downgrade.
    func testInfoPlistNamesTheIconComposerIconAndKeepsTheIcnsFallback() throws {
        let plist = try XCTUnwrap(
            NSDictionary(contentsOf: repositoryRoot.appending(path: "Resources/Info.plist")) as? [String: Any]
        )
        XCTAssertEqual(plist["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "MyTokenRemain.icns")
    }

    func testDockTileDrawsTheIconShapeWhileTheBareLogoStaysTransparent() throws {
        let size = NSSize(width: 256, height: 256)

        // Rasterize into an explicit sRGB context: a TIFF round trip tags the
        // bitmap with a device space and shifts the color being checked.
        func color(_ image: NSImage, x: Int, y: Int) throws -> NSColor {
            let width = Int(size.width), height = Int(size.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            // Row 0 of the buffer is the top of the image.
            let index = ((height - 1 - y) * width + x) * 4
            let alpha = Double(pixels[index + 3]) / 255
            func channel(_ offset: Int) -> Double {
                alpha == 0 ? 0 : Double(pixels[index + offset]) / 255 / alpha
            }
            return NSColor(srgbRed: channel(0), green: channel(1), blue: channel(2), alpha: alpha)
        }

        let tile = MyTokenRemainArtwork.image(
            slots: [.init(provider: .claude, remainingPercent: 60)],
            size: size.width,
            style: .dockTile
        )
        // Outside the 824/1024 shape: transparent, as on any macOS icon grid.
        XCTAssertEqual(try color(tile, x: 4, y: 128).alphaComponent, 0, accuracy: 0.01)
        XCTAssertEqual(try color(tile, x: 30, y: 30).alphaComponent, 0, accuracy: 0.01)
        // Inside it: the Icon Composer navy.
        let inside = try color(tile, x: 128, y: 128)
        XCTAssertEqual(inside.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(inside.redComponent, MyTokenRemainArtwork.dockTileFill.red, accuracy: 0.02)
        XCTAssertEqual(inside.blueComponent, MyTokenRemainArtwork.dockTileFill.blue, accuracy: 0.02)

        let bare = MyTokenRemainArtwork.image(
            slots: [.init(provider: .claude, remainingPercent: 60)],
            size: size.width,
            style: .bare
        )
        XCTAssertEqual(try color(bare, x: 128, y: 128).alphaComponent, 0, accuracy: 0.01)
    }
}
