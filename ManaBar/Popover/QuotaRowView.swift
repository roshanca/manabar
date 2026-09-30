import SwiftUI

/// One quota line: label, mana bar, percentage, reset countdown.
struct QuotaRowView: View {
    let metric: QuotaMetric
    let showRemaining: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(metric.title)
                        .font(.callout)
                        .frame(width: 96, alignment: .leading)
                    QuotaBar(usedRatio: metric.usedRatio)
                    Text(percentText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Text(RelativeReset.format(metric.resetDate, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var percentText: String {
        let used = metric.usedRatio
        if showRemaining {
            return "\(Int(((1 - used) * 100).rounded())) left"
        }
        return "\(Int((used * 100).rounded()))% used"
    }
}
