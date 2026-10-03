import AppKit
import SwiftUI

/// The menu-bar mana bar. Rendered as a plain NSImage (deterministic in the
/// menu bar, unlike arbitrary SwiftUI content). Fill ratio follows the primary
/// provider's configured metric; >80% orange, >95% red + blinking with an
/// optional "Out of mana" easter egg. The blink task only runs while critical,
/// so idle costs zero timer wakeups.
///
/// NOTE: do not use TimelineView or live Text(.timer) here — self-invalidating
/// views in a MenuBarExtra label trigger an update/layout feedback loop
/// (100% CPU, unbounded memory; FB22359008). Manual @State updates are safe.
struct ManaBarLabel: View {
    @Environment(AppState.self) private var appState
    @State private var blinkPhase = false

    private var ratio: Double? { appState.menuBarRatio }
    private var isCritical: Bool {
        (ratio ?? 0) > 0.95 || UserDefaults.standard.bool(forKey: "debugForceCritical")
    }

    var body: some View {
        image
            .opacity(isCritical && blinkPhase ? 0.3 : 1)
            .task(id: isCritical) {
                blinkPhase = false
                while isCritical && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.6))
                    blinkPhase.toggle()
                }
            }
    }

    private var image: some View {
        Image(nsImage: ManaBarImage.make(
            ratio: ratio,
            outOfMana: isCritical && appState.settings.outOfManaAlert))
    }
}

enum ManaBarImage {
    private static let barSize = NSSize(width: 22, height: 9)
    private static let imageHeight: CGFloat = 18

    static func make(ratio: Double?, outOfMana: Bool) -> NSImage {
        let text = outOfMana ? "  Out of mana" : ""
        let textWidth: CGFloat = outOfMana ? 62 : 0
        let size = NSSize(width: barSize.width + textWidth + 2, height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            let barOrigin = NSPoint(x: 1, y: (imageHeight - barSize.height) / 2)
            let barRect = NSRect(origin: barOrigin, size: barSize)

            // Track
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 4.5, yRadius: 4.5).fill()
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(roundedRect: barRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            outline.lineWidth = 1
            outline.stroke()

            // Fill
            if let ratio {
                let clamped = min(max(ratio, 0), 1)
                let fillWidth = max(4, barSize.width * clamped)
                let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
                Self.fillColor(for: clamped).setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 4.5, yRadius: 4.5).fill()
            }

            if outOfMana {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: NSColor.systemRed,
                ]
                text.draw(at: NSPoint(x: barRect.maxX + 2, y: 3), withAttributes: attributes)
            }
            return true
        }
        return image
    }

    private static func fillColor(for ratio: Double) -> NSColor {
        if ratio > 0.95 { return .systemRed }
        if ratio > 0.8 { return .systemOrange }
        return NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1) // mana blue
    }
}
