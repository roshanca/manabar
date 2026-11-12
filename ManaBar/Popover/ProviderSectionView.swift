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

/// Wallet balances (DeepSeek): one block per currency — a large monospaced
/// total over "Topped up" / "Granted" caption rows in the ExtrasView style.
/// The total is red when the account reports unavailable or the balance is
/// exhausted, orange below the configured low-balance threshold, else
/// primary.
private struct WalletBalancesView: View {
    let balances: [WalletBalance]
    let isAvailable: Bool?

    @Environment(AppState.self) private var appState

    var body: some View {
        ForEach(balances) { balance in
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.formatted(balance.total, currency: balance.currency))
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(color(for: balance))
                ExtrasView(extras: [
                    ExtraInfo(id: "\(balance.id).toppedUp", label: "Topped up",
                              value: Self.formatted(balance.toppedUp, currency: balance.currency)),
                    ExtraInfo(id: "\(balance.id).granted", label: "Granted",
                              value: Self.formatted(balance.granted, currency: balance.currency)),
                ])
            }
            .padding(.top, 4)
        }
    }

    private func color(for balance: WalletBalance) -> Color {
        let total = NSDecimalNumber(decimal: balance.total).doubleValue
        if isAvailable == false || total <= 0 { return .red }
        if total < appState.settings.lowBalanceThreshold { return .orange }
        return .primary
    }

    /// "¥36.64" for CNY, "$12.00" for USD, "XXX 1.00" for anything else.
    private static func formatted(_ amount: Decimal, currency: String) -> String {
        let value = String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
        switch currency {
        case "CNY": return "¥\(value)"
        case "USD": return "$\(value)"
        default: return "\(currency) \(value)"
        }
    }
}

/// One provider section: header (icon, name, plan badge, stale badge), quota
/// rows, extras. Sections are separated by dividers, not cards.
struct ProviderSectionView: View {
    let providerID: ProviderID
    @Environment(AppState.self) private var appState

    var body: some View {
        let snapshot = appState.snapshots[providerID]
        let stale = appState.isStale(providerID)
        let failure = appState.failureMessage(providerID)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(providerID.iconAssetName)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
                Text(providerID.displayName)
                    .font(.headline)
                if let plan = snapshot?.planName {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: .capsule)
                }
                if snapshot?.isAvailable == false {
                    Text("Insufficient")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: .capsule)
                        .foregroundStyle(.red)
                }
                Spacer()
                if stale && snapshot != nil {
                    Label("stale", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let snapshot {
                if snapshot.balances.isEmpty {
                    ForEach(snapshot.metrics) { metric in
                        QuotaRowView(metric: metric, showRemaining: appState.settings.showRemaining)
                    }
                } else {
                    WalletBalancesView(balances: snapshot.balances,
                                       isAvailable: snapshot.isAvailable)
                }
                if !snapshot.extras.isEmpty {
                    ExtrasView(extras: snapshot.extras)
                        .padding(.top, 2)
                }
                if let resets = snapshot.resets {
                    ResetsRowView(resets: resets)
                        .padding(.top, 2)
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
