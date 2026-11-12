import Foundation

/// Estimates today's DeepSeek spend from balance changes.
///
/// The balance API only reports the current total, so "spent today" is
/// derived locally: each refresh compares the total against the last seen
/// value. A drop counts as spend; a rise is treated as a top-up and shifts
/// the baseline up. It's an estimate — it only counts while ManaBar is
/// refreshing, top-ups reset the baseline, and expiring granted credit
/// would count as spend. History is cleared when the API key changes
/// (DeepSeekCredentialStore calls `reset`).
enum DeepSeekSpendTracker {
    /// UserDefaults key holding `[currency: ["day": ..., "baseline": ...,
    /// "last": ...]]` — all values are strings.
    private static let storageKey = "deepseekSpendBaseline"

    /// Returns the estimated spend for `currency` since local midnight,
    /// given the balance `total` just fetched. Records are per currency;
    /// a new local day resets the baseline to the current total.
    static func todaySpent(currency: String, total: Decimal,
                           now: Date = Date(), defaults: UserDefaults = .standard) -> Decimal {
        let today = dayString(now)
        var records = load(defaults)

        // No record, a different day, or unparseable values all reset the
        // baseline to the current total.
        var baseline = total
        if let record = records[currency], record["day"] == today,
           let storedBaseline = record["baseline"].flatMap({ Decimal(string: $0) }),
           let last = record["last"].flatMap({ Decimal(string: $0) }) {
            baseline = storedBaseline
            if total > last {
                // Top-up: shift the baseline up by the increase so the
                // added credit doesn't read as negative spend.
                baseline += total - last
            }
        }

        records[currency] = [
            "day": today,
            "baseline": baseline.description,
            "last": total.description,
        ]
        save(records, defaults)
        return max(baseline - total, 0)
    }

    /// Drops all recorded spend history — called when the API key changes,
    /// since a different wallet must not inherit the old baseline.
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    /// Local calendar day as "yyyy-MM-dd".
    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func load(_ defaults: UserDefaults) -> [String: [String: String]] {
        (defaults.dictionary(forKey: storageKey) as? [String: [String: String]]) ?? [:]
    }

    private static func save(_ records: [String: [String: String]], _ defaults: UserDefaults) {
        defaults.set(records, forKey: storageKey)
    }
}
