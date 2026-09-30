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

/// A mana-bar style progress bar.
struct QuotaBar: View {
    let usedRatio: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule()
                    .fill(QuotaColor.color(for: usedRatio))
                    .frame(width: max(height, geometry.size.width * min(max(usedRatio, 0), 1)))
            }
        }
        .frame(height: height)
    }
}
