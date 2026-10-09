import SwiftUI

/// One quota line: title over a full-width mana bar, then percentage and
/// reset countdown side by side underneath.
struct QuotaRowView: View {
    let metric: QuotaMetric
    let showRemaining: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(metric.title)
                    .font(.callout)
                    .padding(.bottom, 7)
                QuotaBar(usedRatio: metric.usedRatio,
                         paceRatio: paceRatio(at: context.date))
                    .padding(.bottom, 5)
                HStack {
                    Text(percentText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(RelativeReset.format(metric.resetDate, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Elapsed-time fraction of the quota window — where the pace tick lands.
    /// Nil when the window can't be derived or barely started (<1% in).
    private func paceRatio(at now: Date) -> Double? {
        guard let reset = metric.resetDate,
              let window = metric.windowSeconds, window > 0 else { return nil }
        let elapsed = window - reset.timeIntervalSince(now)
        guard elapsed > window * 0.01 else { return nil }
        return min(elapsed / window, 1)
    }

    private var percentText: String {
        let used = metric.usedRatio
        if showRemaining {
            return "\(Int(((1 - used) * 100).rounded())) left"
        }
        return "\(Int((used * 100).rounded()))% used"
    }
}
