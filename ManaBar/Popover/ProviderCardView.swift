import SwiftUI

/// Extra label/value rows (Kimi booster balance, Claude extra usage, Codex credits).
struct ExtrasView: View {
    let extras: [ExtraInfo]

    var body: some View {
        ForEach(extras) { extra in
            HStack {
                Text(extra.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(extra.value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One provider card: header (name, plan, stale badge), quota rows, extras.
struct ProviderCardView: View {
    let providerID: ProviderID
    @Environment(AppState.self) private var appState

    var body: some View {
        let snapshot = appState.snapshots[providerID]
        let stale = appState.isStale(providerID)
        let failure = appState.failureMessage(providerID)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(providerID.displayName)
                    .font(.headline)
                if let plan = snapshot?.planName {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: .capsule)
                }
                Spacer()
                if stale && snapshot != nil {
                    Label("stale", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let snapshot {
                ForEach(snapshot.metrics) { metric in
                    QuotaRowView(metric: metric, showRemaining: appState.settings.showRemaining)
                }
                if !snapshot.extras.isEmpty {
                    ExtrasView(extras: snapshot.extras)
                }
                if stale, let fetched = snapshot.fetchedAt as Date? {
                    Text("updated \(RelativeReset.ageString(fetched))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .opacity(stale && snapshot != nil ? 0.65 : 1)
    }
}

extension RelativeReset {
    /// "just now", "5m ago", "2h ago" — for stale timestamps.
    static func ageString(_ date: Date, now: Date = Date()) -> String {
        let interval = max(now.timeIntervalSince(date), 0)
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 1 { return "just now" }
        if totalMinutes < 60 { return "\(totalMinutes)m ago" }
        return "\(totalMinutes / 60)h ago"
    }
}
