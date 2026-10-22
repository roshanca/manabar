import AppKit

/// Icon + percentage strip — every enabled provider gets a slot, an
/// alternative to the mana bar. Rendered as one NSImage for the same
/// determinism reason as ManaBarImage. Percentages carry the shared
/// severity scale (label color → orange >80% → red >95%); a slot without
/// data draws "--" dimmed so positions never shift. A weekly-window
/// percentage carries a superscript "w" marker.
enum MenuBarIconsImage {
    private static let imageHeight: CGFloat = 18
    private static let iconSize: CGFloat = 12
    private static let iconTextGap: CGFloat = 3
    private static let itemGap: CGFloat = 9
    private static let edgeInset: CGFloat = 1

    static func make(entries: [(provider: ProviderID, metric: QuotaMetric?)],
                     showRemaining: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let markerFont = NSFont.systemFont(ofSize: 6.5, weight: .semibold)
        struct Item {
            let provider: ProviderID? // nil icon for the empty-state dash
            let text: NSString
            let textSize: NSSize
            /// "w" for a weekly window, nil otherwise.
            let marker: NSString?
            let markerSize: NSSize
            let usedRatio: Double?
        }
        var items = entries.map { entry -> Item in
            let text: String
            let marker: String?
            if let metric = entry.metric {
                let shown = showRemaining ? 1 - metric.usedRatio : metric.usedRatio
                text = "\(Int((shown * 100).rounded()))%"
                marker = metric.kind == .weekly ? "w" : nil
            } else {
                text = "--"
                marker = nil
            }
            let nsText = NSString(string: text)
            let nsMarker = marker.map(NSString.init(string:))
            return Item(provider: entry.provider, text: nsText,
                        textSize: nsText.size(withAttributes: [.font: font]),
                        marker: nsMarker,
                        markerSize: nsMarker?.size(withAttributes: [.font: markerFont]) ?? .zero,
                        usedRatio: entry.metric?.usedRatio)
        }
        // Keep the status item clickable even with no providers enabled.
        if items.isEmpty {
            let dash = NSString(string: "--")
            items = [Item(provider: nil, text: dash,
                          textSize: dash.size(withAttributes: [.font: font]),
                          marker: nil, markerSize: .zero, usedRatio: nil)]
        }

        let width = items.reduce(0) {
            $0 + ($1.provider == nil ? 0 : Self.iconSize + iconTextGap)
                + $1.textSize.width + $1.markerSize.width
        } + itemGap * CGFloat(max(items.count - 1, 0)) + edgeInset * 2
        let size = NSSize(width: ceil(width), height: imageHeight)

        let image = NSImage(size: size, flipped: false) { _ in
            var x = edgeInset
            for item in items {
                if let provider = item.provider,
                   let icon = NSImage(named: provider.iconAssetName) {
                    let iconRect = NSRect(x: x, y: (imageHeight - iconSize) / 2,
                                          width: iconSize, height: iconSize)
                    icon.draw(in: iconRect)
                    // The assets are template-intent but draw literally here;
                    // punch labelColor through their alpha so they track the
                    // menu bar's light/dark appearance.
                    let alpha: CGFloat = item.usedRatio == nil ? 0.35 : 1
                    NSColor.labelColor.withAlphaComponent(alpha).set()
                    iconRect.fill(using: .sourceIn)
                    x += iconSize + iconTextGap
                }
                let color = item.usedRatio.map { ManaBarImage.fillColor(for: $0, normal: .labelColor) }
                    ?? NSColor.labelColor.withAlphaComponent(0.35)
                let textY = max(0, (imageHeight - item.textSize.height) / 2)
                item.text.draw(at: NSPoint(x: x, y: textY),
                               withAttributes: [.font: font, .foregroundColor: color])
                x += item.textSize.width
                if let marker = item.marker {
                    // Superscript: marker top rides on the text's cap top.
                    let markerY = textY + item.textSize.height - item.markerSize.height
                    marker.draw(at: NSPoint(x: x, y: markerY + 1),
                                withAttributes: [.font: markerFont, .foregroundColor: color])
                    x += item.markerSize.width
                }
                x += itemGap
            }
            return true
        }
        image.accessibilityDescription = entries.map { entry in
            guard let metric = entry.metric else { return "\(entry.provider.displayName): no data" }
            return "\(entry.provider.displayName): \(Int((metric.usedRatio * 100).rounded()))% used"
        }.joined(separator: ". ")
        return image
    }
}
