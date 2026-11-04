import SwiftUI

/// Interactive "Limit resets" row for providers with spendable reset credits
/// (Codex rate-limit reset credits today). The collapsed row matches the
/// extras styling — label left, "N available" right; tapping it expands an
/// earliest-first list of the unexpired credits, where only the earliest
/// carries a Use button. Use swaps the list for an inline confirm; a
/// confirmed claim spends one credit and the post-claim refresh drops the
/// count in place.
struct ResetsRowView: View {
    let resets: ResetCredits
    @Environment(AppState.self) private var appState

    /// The row's step in the use flow. `.result` keeps the outcome visible;
    /// `retryable` marks transport failures where Try again replays the same
    /// idempotency key.
    private enum Phase: Equatable {
        case list
        case confirm
        case claiming
        case result(message: String, retryable: Bool, isError: Bool)
    }

    @State private var expanded = false
    @State private var phase: Phase = .list
    /// Minted once per view; a fresh key replaces it after every definitive
    /// outcome, so only a transport-failure retry replays the same pair.
    @State private var requestID = UUID().uuidString

    private var canUse: Bool { resets.usableNow != 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded {
                switch phase {
                case .list: list
                case .confirm: confirm
                case .claiming: claiming
                case .result(let message, let retryable, let isError):
                    result(message, retryable: retryable, isError: isError)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                expanded.toggle()
                if !expanded { phase = .list }
            }
        } label: {
            HStack {
                Text("Limit resets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(resets.count) available")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Credit list

    private var list: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                if resets.expiries.isEmpty {
                    // The detail list is best-effort; the claim re-fetches it,
                    // so Use still works when expiries never arrived.
                    entry(dot: severityColor(nil, now: context.date),
                          label: "Earliest credit",
                          detail: "expiry unknown",
                          showUse: true)
                } else {
                    ForEach(Array(resets.expiries.enumerated()), id: \.offset) { index, expiry in
                        entry(dot: severityColor(expiry, now: context.date),
                              label: expiryLabel(expiry),
                              detail: countdown(expiry, now: context.date),
                              showUse: index == 0)
                    }
                }
            }
        }
    }

    private func entry(dot: Color, label: String, detail: String, showUse: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showUse && canUse {
                Button("Use") { phase = .confirm }
                    .controlSize(.mini)
            } else {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Confirm / claim / result

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Use a limit reset?")
                .font(.caption.weight(.semibold))
            Text("Spends your earliest credit to reset Codex limits now. This can't be undone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Use reset") { claim() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Cancel") { phase = .list }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }

    private var claiming: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("Using reset…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func result(_ message: String, retryable: Bool, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if retryable {
                    Button("Try again") { claim() }
                        .controlSize(.small)
                }
                Button("Dismiss") { phase = .list }
                    .controlSize(.small)
            }
        }
    }

    private func claim() {
        phase = .claiming
        let key = requestID
        Task {
            let outcome = await appState.claimCodexReset(redeemRequestID: key)
            switch outcome {
            case .success:
                phase = .result(message: "Reset claimed — limits refreshing.", retryable: false, isError: false)
            case .nothingToReset:
                phase = .result(message: "Nothing to reset yet — the current limits are still running.", retryable: false, isError: false)
            case .noCredit:
                phase = .result(message: "That reset is no longer available.", retryable: false, isError: true)
            case .authExpired:
                phase = .result(message: "Codex sign-in expired — re-run codex login.", retryable: false, isError: true)
            case .failed(let message):
                phase = .result(message: message, retryable: true, isError: true)
            }
            // A definitive outcome spends the key; only a lost-answer retry
            // (Try again above) replays it.
            if case .failed = outcome { return }
            requestID = UUID().uuidString
        }
    }

    // MARK: - Formatting

    /// "tomorrow at 9:00 PM", "Sunday at 9:00 PM", "Nov 28 at 12:00 AM".
    private func expiryLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        if date.timeIntervalSinceNow < 7 * 86_400 {
            return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }

    private func countdown(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        return interval <= 0 ? "expired" : RelativeReset.durationString(interval)
    }

    /// Expiry-warning dot colors: red under 48 h, orange under 7 d,
    /// mana blue otherwise. nil expiry (detail list missing) is neutral.
    private func severityColor(_ expiry: Date?, now: Date) -> Color {
        guard let expiry else { return .secondary }
        let remaining = expiry.timeIntervalSince(now)
        if remaining < 48 * 3600 { return .red }
        if remaining < 7 * 86_400 { return .orange }
        return Color(red: 0.25, green: 0.55, blue: 1.0)
    }
}
