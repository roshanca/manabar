import Foundation

/// Failure categories shared by all providers. Drives stale-data behavior:
/// the last good snapshot is always preserved and marked stale on failure.
enum ProviderFailure: Error, Sendable {
    /// Credentials are missing entirely (e.g. CLI not logged in, no API key set).
    case notConfigured(String)
    /// Credentials exist but were rejected (invalid_grant, repeated 401) — re-login needed.
    case authExpired(String)
    /// Network errors, 5xx, rate limiting, unparseable responses.
    case transient(String)

    var userMessage: String {
        switch self {
        case .notConfigured(let m), .authExpired(let m), .transient(let m): m
        }
    }
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage() async throws -> ProviderSnapshot
}

extension UsageProvider {
    /// Maps low-level errors into ProviderFailure.
    func mapError(_ error: Error, provider name: String) -> ProviderFailure {
        if let failure = error as? ProviderFailure { return failure }
        if let http = error as? HTTPError {
            switch http {
            case .badStatus(let code) where code >= 500:
                return .transient("\(name) server error (\(code)); will retry.")
            case .badStatus(429):
                return .transient("\(name) rate limited the request; will retry.")
            case .badStatus(let code):
                return .transient("\(name) request failed (HTTP \(code)).")
            case .badResponse:
                return .transient("\(name) returned an invalid response.")
            }
        }
        if error is DecodingError {
            return .transient("Could not parse \(name) usage response.")
        }
        return .transient("\(name) could not be refreshed.")
    }
}
