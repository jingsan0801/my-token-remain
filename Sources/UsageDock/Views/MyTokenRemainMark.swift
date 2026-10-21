import SwiftUI

/// Compact brand mark for the Dashboard sidebar, derived from the
/// countdown-ring logo. Drawing it in SwiftUI keeps it crisp at any size and
/// avoids shipping a second raster asset.
struct MyTokenRemainMark: View {
    var size: CGFloat

    private static let teal = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
    private static let tile = Color(red: 0x08 / 255, green: 0x14 / 255, blue: 0x31 / 255)

    var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            let tileRect = CGRect(
                x: center.x - side / 2,
                y: center.y - side / 2,
                width: side,
                height: side
            )
            context.fill(
                Path(roundedRect: tileRect, cornerRadius: side * 0.24, style: .continuous),
                with: .color(Self.tile)
            )

            let radius = side * 0.30
            var ticks = Path()
            for index in 0..<12 {
                let angle = Angle.degrees(-90 + Double(index) * 30).radians
                let inner = radius * 1.23
                let outer = radius * 1.43
                ticks.move(to: CGPoint(
                    x: center.x + cos(angle) * inner,
                    y: center.y + sin(angle) * inner
                ))
                ticks.addLine(to: CGPoint(
                    x: center.x + cos(angle) * outer,
                    y: center.y + sin(angle) * outer
                ))
            }
            context.stroke(
                ticks,
                with: .color(Self.teal.opacity(0.22)),
                style: StrokeStyle(lineWidth: side * 0.025, lineCap: .round)
            )

            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(10),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(Self.teal),
                style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round)
            )

            let endAngle = Angle.degrees(10).radians
            let dotRadius = side * 0.045
            let dotCenter = CGPoint(
                x: center.x + cos(endAngle) * radius,
                y: center.y + sin(endAngle) * radius
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: dotCenter.x - dotRadius,
                    y: dotCenter.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(Self.teal)
            )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MyTokenRemain")
    }
}
