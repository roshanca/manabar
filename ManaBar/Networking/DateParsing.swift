import Foundation

/// Tolerant date parsing for the various provider response formats:
/// ISO-8601 with/without fractional seconds, epoch seconds, epoch milliseconds.
enum DateParsing {
    // ISO8601DateFormatter is thread-safe for parsing; marked unsafe to satisfy strict concurrency.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        if let date = isoFractional.date(from: string) { return date }
        if let date = iso.date(from: string) { return date }
        if let epoch = Double(string) {
            return epoch > 1e12
                ? Date(timeIntervalSince1970: epoch / 1000)
                : Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    static func parse(epochSeconds value: Double?) -> Date? {
        value.map { Date(timeIntervalSince1970: $0) }
    }
}
