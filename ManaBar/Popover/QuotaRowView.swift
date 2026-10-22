import SwiftUI

/// One quota line: label over reset countdown at left, mana bar in the
/// middle, bold percentage at right. Bar and percentage share the semantic
/// quota color (mana blue → orange >80% → red >95%).
struct QuotaRowView: View {
    let metric: QuotaMetric
    let showRemaining: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let pace = paceResult(at: now)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.callout.weight(.medium))
                Text(RelativeReset.format(metric.resetDate, now: now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            QuotaBar(usedRatio: metric.usedRatio,
                     paceRatio: pace?.paceRatio,
                     height: 6)

            Text(percentText)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(QuotaColor.color(for: metric.usedRatio))
                .frame(minWidth: 36, alignment: .trailing)
        }
    }

    /// Pace tick position for this window — nil when there's no signal
    /// (window unknown, barely started, or already reset).
    private func paceResult(at now: Date) -> Pace.Result? {
        guard let reset = metric.resetDate,
              let window = metric.windowSeconds else { return nil }
        return Pace.evaluate(resetDate: reset, windowSeconds: window, now: now)
    }

    private var percentText: String {
        let used = metric.usedRatio
        if showRemaining {
            return "\(Int(((1 - used) * 100).rounded())) left"
        }
        return "\(Int((used * 100).rounded()))%"
    }
}
