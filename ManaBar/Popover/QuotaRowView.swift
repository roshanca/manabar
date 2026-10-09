import SwiftUI

/// One quota line: title over a full-width mana bar, then percentage and
/// reset countdown side by side underneath, plus a pace line (delta and
/// run-out projection) when the window timing is known.
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
        return VStack(alignment: .leading, spacing: 0) {
            Text(metric.title)
                .font(.callout)
                .padding(.bottom, 7)
            QuotaBar(usedRatio: metric.usedRatio,
                     paceRatio: pace?.paceRatio)
                .padding(.bottom, 5)
            HStack {
                Text(percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(RelativeReset.format(metric.resetDate, now: now))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let pace {
                HStack {
                    Text(pace.deltaText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(pace.status == .deficit ? Color.red : Color.secondary)
                    Spacer()
                    Text(pace.runOutText(untilReset: metric.resetDate?.timeIntervalSince(now) ?? 0))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 3)
            }
        }
    }

    /// Pace evaluation for this window — nil when there's no signal (window
    /// unknown, barely started, or already reset).
    private func paceResult(at now: Date) -> Pace.Result? {
        guard let reset = metric.resetDate,
              let window = metric.windowSeconds else { return nil }
        return Pace.evaluate(usedRatio: metric.usedRatio, resetDate: reset,
                             windowSeconds: window, now: now)
    }

    private var percentText: String {
        let used = metric.usedRatio
        if showRemaining {
            return "\(Int(((1 - used) * 100).rounded())) left"
        }
        return "\(Int((used * 100).rounded()))% used"
    }
}
