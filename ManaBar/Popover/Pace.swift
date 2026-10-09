import Foundation

/// Burn-rate pacing for a quota window — adapted from OpenUsage's `Pace.swift`
/// (MIT — see NOTICE), rewritten around a ±5pp delta tolerance.
///
/// The pace tick marks *expected* usage: the elapsed fraction of the window.
/// The window start is always `resetDate − windowSeconds`, never a calendar
/// day/week assumption. Delta is the gap between actual and expected
/// remaining quota, in percentage points:
///
///     delta = pace − usedRatio = actualRemaining − expectedRemaining
///
/// Positive → reserve (under-consuming), negative → deficit (burning ahead
/// of the window).
///
/// Pure logic (no SwiftUI) so it stays unit-testable.
enum Pace {
    /// |delta| within this ratio (±5pp) still counts as on pace — a product
    /// tolerance, not an industry standard.
    static let toleranceRatio = 0.05

    enum Status {
        case reserve   // delta > +5pp — projected to finish with quota to spare
        case onPace    // |delta| ≤ 5pp
        case deficit   // delta < −5pp — projected to run out before reset
    }

    struct Result {
        /// Elapsed-time fraction of the window — where the pace tick lands.
        let paceRatio: Double
        /// pace − usedRatio as a fraction (×100 = percentage points).
        let deltaRatio: Double
        let status: Status
        /// Seconds until the quota is gone at the window's average burn rate —
        /// `(1 − usedRatio) / (usedRatio / elapsed)`. nil when nothing has been
        /// consumed yet: no rate to project, and it trivially lasts.
        let secondsToRunOut: TimeInterval?
    }

    /// Minimum time into the window before the math is meaningful — avoids
    /// dividing by a few elapsed seconds on a coarse whole-percent meter.
    static func minimumElapsed(window: TimeInterval) -> TimeInterval {
        max(60, window * 0.01)
    }

    /// Full pace evaluation, or nil when there's no signal: no window, window
    /// not yet started, already reset, or too early for a stable read.
    static func evaluate(usedRatio: Double, resetDate: Date, windowSeconds: TimeInterval,
                         now: Date = Date()) -> Result? {
        guard windowSeconds > 0 else { return nil }
        let elapsed = now.timeIntervalSince(resetDate.addingTimeInterval(-windowSeconds))
        let untilReset = resetDate.timeIntervalSince(now)
        guard elapsed >= minimumElapsed(window: windowSeconds), untilReset > 0 else { return nil }

        let pace = min(elapsed / windowSeconds, 1)
        let delta = pace - usedRatio
        let status: Status = delta > toleranceRatio ? .reserve
            : delta < -toleranceRatio ? .deficit : .onPace
        let runOut = usedRatio > 0 ? max((1 - usedRatio) * elapsed / usedRatio, 0) : nil
        return Result(paceRatio: pace, deltaRatio: delta, status: status,
                      secondsToRunOut: runOut)
    }
}

extension Pace.Result {
    /// "+71pp reserve", "17pp deficit", "on pace".
    var deltaText: String {
        let pp = Int((abs(deltaRatio) * 100).rounded())
        return switch status {
        case .reserve: "+\(pp)pp reserve"
        case .deficit: "\(pp)pp deficit"
        case .onPace: "on pace"
        }
    }

    /// "runs out in 17h 30m" when the projection lands before reset ("runs out
    /// now" once spent), else "lasts until reset" — Devin panel wording.
    func runOutText(untilReset: TimeInterval) -> String {
        guard let eta = secondsToRunOut, eta < untilReset else {
            return "lasts until reset"
        }
        return eta <= 0 ? "runs out now"
            : "runs out in \(RelativeReset.durationString(eta))"
    }
}
