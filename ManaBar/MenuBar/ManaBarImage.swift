import AppKit

/// Renders the mana bar as a plain NSImage (deterministic in the menu bar,
/// unlike arbitrary SwiftUI content). Single-window modes draw one 22×9
/// bar; `.dual` draws two 22×5 bars stacked 2pt apart — session on top,
/// weekly below. Slots without data keep an unfilled track so positions
/// never shift. Fill follows each window's own usedRatio: >80% orange,
/// >95% red.
enum ManaBarImage {
    private static let imageHeight: CGFloat = 18
    private static let barGap: CGFloat = 2

    static func make(bars: [MenuBarBar], outOfMana: Bool) -> NSImage {
        let text = outOfMana ? "  Out of mana" : ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.systemRed,
        ]
        let textWidth = outOfMana ? ceil(text.size(withAttributes: attributes).width) : 0
        let barSize = NSSize(width: 22, height: bars.count > 1 ? 5 : 9)
        let stackHeight = barSize.height * CGFloat(bars.count)
            + barGap * CGFloat(max(bars.count - 1, 0))
        let size = NSSize(width: barSize.width + textWidth + 2, height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            let stackBase = (imageHeight - stackHeight) / 2
            for (index, bar) in bars.enumerated() {
                // Index 0 is the topmost bar; this context is not flipped.
                let barRect = NSRect(
                    x: 1,
                    y: stackBase + stackHeight
                        - (barSize.height + barGap) * CGFloat(index) - barSize.height,
                    width: barSize.width, height: barSize.height)
                drawBar(barRect, ratio: bar.metric?.usedRatio)
            }

            if outOfMana {
                text.draw(at: NSPoint(x: barSize.width + 3, y: 3), withAttributes: attributes)
            }
            return true
        }
        image.accessibilityDescription = accessibilityLabel(for: bars)
        return image
    }

    private static func drawBar(_ rect: NSRect, ratio: Double?) {
        let radius = rect.height / 2

        // Track
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: radius - 0.5, yRadius: radius - 0.5)
        outline.lineWidth = 1
        outline.stroke()

        // Fill
        if let ratio {
            let clamped = min(max(ratio, 0), 1)
            let fillWidth = max(4, rect.width * clamped)
            let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            fillColor(for: clamped).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    /// Shared severity scale: `normal` below 80%, orange >80%, red >95%.
    /// Icons+% strips pass `normal: .labelColor` — neutral until hot.
    static func fillColor(for ratio: Double,
                          normal: NSColor = NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1)) -> NSColor {
        if ratio > 0.95 { return .systemRed }
        if ratio > 0.8 { return .systemOrange }
        return normal
    }

    /// VoiceOver summary per bar — keeps "no data" distinguishable from a
    /// real 0% reading.
    private static func accessibilityLabel(for bars: [MenuBarBar]) -> String {
        bars.map { bar in
            let name = bar.metric?.title
                ?? (bar.kind == .session ? "Session quota" : "Weekly quota")
            guard let ratio = bar.metric?.usedRatio else { return "\(name): no data" }
            return "\(name): \(Int((ratio * 100).rounded()))% used"
        }.joined(separator: ". ")
    }
}
