import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case kimi
    case claudeCode
    case codex
    case devin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kimi: "Kimi Coding Plan"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .devin: "Devin"
        }
    }
}

/// Which quota window a metric represents; used for menu-bar metric selection.
enum MetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case session
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: "5h / session"
        case .weekly: "Weekly"
        }
    }
}

struct QuotaMetric: Sendable, Identifiable {
    let id: String
    let kind: MetricKind?
    let title: String
    /// 0...1, fraction of the quota already consumed.
    let usedRatio: Double
    let resetDate: Date?
}

/// A free-form label/value row shown under a provider's metrics
/// (Kimi booster balance, Claude extra usage, Codex credits, ...).
struct ExtraInfo: Sendable, Identifiable {
    let id: String
    let label: String
    let value: String
}

struct ProviderSnapshot: Sendable {
    let providerID: ProviderID
    var planName: String?
    var metrics: [QuotaMetric]
    var extras: [ExtraInfo]
    let fetchedAt: Date
}
