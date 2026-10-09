import SwiftUI

/// Relative reset countdown: "now", "in 45m", "in 1h 50m", "in 3d 2h".
enum RelativeReset {
    static func format(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "resetting now" }
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(max(minutes, 1))m"
    }
}

/// Shared color for a used-ratio: mana blue → orange >80% → red >95%.
enum QuotaColor {
    static func color(for usedRatio: Double) -> Color {
        if usedRatio > 0.95 { return .red }
        if usedRatio > 0.8 { return .orange }
        return Color(red: 0.25, green: 0.55, blue: 1.0) // mana blue
    }
}

/// A mana-bar style progress bar. `paceRatio` (elapsed-time fraction of the
/// quota window) draws a pace tick — a thin line with a small gap cut into
/// the bar on either side, the convention OpenUsage and similar trackers
/// use: red when the current burn rate overshoots the limit before reset,
/// neutral otherwise.
struct QuotaBar: View {
    let usedRatio: Double
    var paceRatio: Double? = nil
    var height: CGFloat = 8

    private let lineWidth: CGFloat = 2
    private let lineGap: CGFloat = 1.5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(QuotaColor.color(for: usedRatio))
                        .frame(width: max(height, geometry.size.width * min(max(usedRatio, 0), 1)))
                }
                .mask { barMask(width: geometry.size.width) }

                if let paceRatio {
                    Capsule()
                        .fill(tickColor(pace: paceRatio))
                        .frame(width: lineWidth, height: height)
                        .offset(x: tickX(width: geometry.size.width, pace: paceRatio) - lineWidth / 2)
                }
            }
        }
        .frame(height: height)
    }

    private var notch: CGFloat { lineWidth + lineGap * 2 }

    private func tickX(width: CGFloat, pace: Double) -> CGFloat {
        min(max(width * min(max(pace, 0), 1), notch / 2), width - notch / 2)
    }

    /// Erases a `notch`-wide column through the bar at the pace position, so
    /// the tick line sits in a gap punched through fill and track alike.
    @ViewBuilder
    private func barMask(width: CGFloat) -> some View {
        if let paceRatio {
            let x = tickX(width: width, pace: paceRatio)
            HStack(spacing: notch) {
                Rectangle().frame(width: max(x - notch / 2, 0))
                Rectangle()
            }
        } else {
            Rectangle()
        }
    }

    private func tickColor(pace: Double) -> Color {
        pace > 0 && usedRatio / pace > 1 ? .red : .primary.opacity(0.6)
    }
}
