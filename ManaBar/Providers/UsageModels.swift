import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case kimi
    case claudeCode
    case codex
    case devin
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kimi: "Kimi Coding Plan"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .devin: "Devin"
        case .deepseek: "DeepSeek"
        }
    }

    var iconAssetName: String {
        switch self {
        case .kimi: "ProviderKimi"
        case .claudeCode: "ProviderClaude"
        case .codex: "ProviderCodex"
        case .devin: "ProviderDevin"
        case .deepseek: "ProviderDeepSeek"
        }
    }

    /// DeepSeek only reports a wallet balance — nothing quota-like to draw
    /// in the menu bar, so it stays popover-only.
    var showsInMenuBar: Bool { self != .deepseek }
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

    /// Known length of the quota window in seconds — passed explicitly to
    /// `QuotaMetric.windowSeconds` to place the pace tick.
    var defaultWindowSeconds: TimeInterval {
        switch self {
        case .session: 18_000
        case .weekly: 604_800
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
    /// Window length in seconds; window start is `resetDate − windowSeconds`.
    /// Providers must pass it explicitly — pace math never assumes a calendar
    /// day/week. nil means no pace tick or projection.
    let windowSeconds: TimeInterval?

    init(id: String, kind: MetricKind?, title: String, usedRatio: Double,
         resetDate: Date?, windowSeconds: TimeInterval?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.usedRatio = usedRatio
        self.resetDate = resetDate
        self.windowSeconds = windowSeconds
    }
}

/// One slot in the menu-bar image, ordered top → bottom. `metric` nil means
/// no data for that window — the slot keeps an unfilled track (not the same
/// as 0% used) and never counts toward the critical alert.
struct MenuBarBar {
    /// The window this slot represents — also labels the slot when `metric`
    /// is nil so "no data" stays distinguishable.
    let kind: MetricKind
    let metric: QuotaMetric?
}

/// A free-form label/value row shown under a provider's metrics
/// (Kimi booster balance, Claude extra usage, Codex credits, ...).
struct ExtraInfo: Sendable, Identifiable {
    let id: String
    let label: String
    let value: String
}

/// One currency's wallet balance (DeepSeek `balance_infos` entry): the
/// total plus its topped-up and plan-granted components.
struct WalletBalance: Sendable, Identifiable {
    let currency: String
    let total: Decimal
    let granted: Decimal
    let toppedUp: Decimal

    var id: String { currency }
}

/// Banked usage-limit resets a provider lets the user spend from the panel
/// (Codex rate-limit reset credits today). Attached to the snapshot so the
/// popover row stays data-driven; nil when there's nothing to show.
struct ResetCredits: Sendable {
    /// Credits the account holds (the API's `available_count`).
    var count: Int
    /// `applicable_available_count` — the subset the server thinks would take
    /// effect right now (0 when no window needs resetting). A hint, not a
    /// gate: Use stays available and the consume answer is authoritative.
    var usableNow: Int?
    /// Expiries of the available credits, earliest first. May be empty when
    /// the detail endpoint fails — the row then shows just the count.
    var expiries: [Date]
}

struct ProviderSnapshot: Sendable {
    let providerID: ProviderID
    var planName: String?
    var metrics: [QuotaMetric]
    var extras: [ExtraInfo]
    let fetchedAt: Date
    var resets: ResetCredits? = nil
    /// Per-currency wallet balances (DeepSeek). Empty for quota providers;
    /// when non-empty the popover renders the wallet block instead of rows.
    var balances: [WalletBalance] = []
    /// Server-reported availability flag (DeepSeek `is_available`); nil
    /// when the provider doesn't report one.
    var isAvailable: Bool? = nil
}
