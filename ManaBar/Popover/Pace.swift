import Foundation

/// Burn-rate pacing for a quota window — adapted from OpenUsage's `Pace.swift`
/// (MIT — see NOTICE).
///
/// The pace tick marks *expected* usage: the elapsed fraction of the window.
/// The window start is always `resetDate − windowSeconds`, never a calendar
/// day/week assumption.
///
/// Pure logic (no SwiftUI) so it stays unit-testable.
enum Pace {
    /// |used − pace| beyond this ratio (5pp) marks the tick orange — a
    /// product tolerance, not an industry standard.
    static let toleranceRatio = 0.05

    struct Result {
        /// Elapsed-time fraction of the window — where the pace tick lands.
        let paceRatio: Double
    }

    /// Minimum time into the window before the math is meaningful — avoids
    /// dividing by a few elapsed seconds on a coarse whole-percent meter.
    static func minimumElapsed(window: TimeInterval) -> TimeInterval {
        max(60, window * 0.01)
    }

    /// Pace tick position, or nil when there's no signal: window not yet
    /// started, already reset, or too early for a stable read.
    static func evaluate(resetDate: Date, windowSeconds: TimeInterval,
                         now: Date = Date()) -> Result? {
        guard windowSeconds > 0 else { return nil }
        let elapsed = now.timeIntervalSince(resetDate.addingTimeInterval(-windowSeconds))
        let untilReset = resetDate.timeIntervalSince(now)
        guard elapsed >= minimumElapsed(window: windowSeconds), untilReset > 0 else { return nil }
        return Result(paceRatio: min(elapsed / windowSeconds, 1))
    }
}
