import AppKit
import SwiftUI
import Testing
@testable import UsageDock

@MainActor
@Suite("MyTokenRemain brand mark")
struct MyTokenRemainMarkTests {
    @Test("The sidebar mark renders a teal arc on a dark tile")
    func rendersVisibleArtwork() throws {
        let renderer = ImageRenderer(content: MyTokenRemainMark(size: 84))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))

        if let path = ProcessInfo.processInfo.environment["MYTOKENREMAIN_WRITE_MARK"] {
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }

        var tealPixels = 0
        var tilePixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else { continue }
                if color.greenComponent > 0.55,
                   color.blueComponent > 0.35,
                   color.redComponent < 0.45 {
                    tealPixels += 1
                }
                if color.redComponent < 0.15,
                   color.greenComponent < 0.20,
                   color.blueComponent < 0.35 {
                    tilePixels += 1
                }
            }
        }

        #expect(tealPixels > 20)
        #expect(tilePixels > 500)
    }

    @Test("The Dock artwork draws the ring and provider meters")
    func dockArtworkRenders() throws {
        let image = MyTokenRemainArtwork.image(
            slots: [
                .init(provider: .claude, remainingPercent: 62),
                .init(provider: .codex, remainingPercent: 24)
            ],
            size: 256,
            style: .dockTile
        )
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        if let path = ProcessInfo.processInfo.environment["MYTOKENREMAIN_WRITE_DOCK"] {
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
        // Outside the 824/1024 icon shape is transparent.
        #expect(abs((bitmap.colorAt(x: 4, y: 128)?.alphaComponent ?? 1)) < 0.01)
        // The tile centre is the opaque navy fill.
        let center = try #require(bitmap.colorAt(x: 128, y: 128)?.usingColorSpace(.sRGB))
        #expect(abs(center.alphaComponent - 1) < 0.01)
        #expect(
            abs(Double(center.redComponent) - MyTokenRemainArtwork.dockTileFill.red) < 0.03
        )
    }
}
