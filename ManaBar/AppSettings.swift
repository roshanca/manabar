import Foundation

/// User-facing preferences, persisted in UserDefaults. (Named AppSettings to
/// avoid colliding with SwiftUI's `Settings` scene.)
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
        case manual = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case thirtyMinutes = 1800
        case oneHour = 3600

        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue) }

        var label: String {
            switch self {
            case .manual: "Manual"
            case .oneMinute: "Every minute"
            case .fiveMinutes: "Every 5 minutes"
            case .fifteenMinutes: "Every 15 minutes"
            case .thirtyMinutes: "Every 30 minutes"
            case .oneHour: "Every hour"
            }
        }
    }

    /// Menu-bar presentation: the mana bar for the primary provider, or an
    /// icon + percentage slot for every enabled provider.
    enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
        case manaBar
        case providers

        var id: String { rawValue }

        var label: String {
            switch self {
            case .manaBar: "Mana bar"
            case .providers: "Icons + %"
            }
        }
    }

    /// How a provider's quota appears in the menu bar: one window, or both
    /// stacked (short-period on top, weekly below). Raw values stay
    /// compatible with the MetricKind strings persisted by older builds —
    /// this is a display mode, not a quota window, so MetricKind stays
    /// session/weekly only.
    enum MenuBarDisplay: String, CaseIterable, Identifiable, Sendable {
        case session
        case weekly
        case dual

        var id: String { rawValue }

        /// Per-provider option label — Devin's short window is daily, not 5h.
        func label(for provider: ProviderID) -> String {
            switch self {
            case .session: provider == .devin ? "Daily / session" : "5h / session"
            case .weekly: "Weekly"
            case .dual: "Both"
            }
        }
    }

    private let defaults = UserDefaults.standard

    var enabledProviders: Set<ProviderID> {
        didSet { defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: "enabledProviders") }
    }
    /// The provider whose quota drives the menu-bar mana bar.
    var primaryProvider: ProviderID {
        didSet { defaults.set(primaryProvider.rawValue, forKey: "primaryProvider") }
    }
    /// Mana bar vs. per-provider icon+% strip.
    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    /// Which display mode (session/weekly/dual) each provider uses in the
    /// menu bar when primary.
    var menuBarMetric: [ProviderID: MenuBarDisplay] {
        didSet { defaults.set(menuBarMetric.mapValues(\.rawValue), forKey: "menuBarMetric") }
    }
    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }
    /// true → show "77 left", false → show "23% used".
    var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: "showRemaining") }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    /// Easter egg: show an "Out of mana" label when the bar is critical.
    var outOfManaAlert: Bool {
        didSet { defaults.set(outOfManaAlert, forKey: "outOfManaAlert") }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.stringArray(forKey: "enabledProviders") {
            enabledProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        } else {
            enabledProviders = Set(ProviderID.allCases)
        }
        primaryProvider = defaults.string(forKey: "primaryProvider")
            .flatMap(ProviderID.init(rawValue:)) ?? .kimi
        menuBarStyle = defaults.string(forKey: "menuBarStyle")
            .flatMap(MenuBarStyle.init(rawValue:)) ?? .manaBar
        menuBarMetric = (defaults.dictionary(forKey: "menuBarMetric") as? [String: String])?
            .reduce(into: [:]) { result, pair in
                guard let provider = ProviderID(rawValue: pair.key),
                      let kind = MenuBarDisplay(rawValue: pair.value) else { return }
                result[provider] = kind
            } ?? [:]
        if let rawInterval = defaults.object(forKey: "refreshInterval") as? Int,
           let interval = RefreshInterval(rawValue: rawInterval) {
            refreshInterval = interval
        } else {
            // NB: defaults.integer(forKey:) returns 0 for missing keys, and
            // rawValue 0 means .manual — never read this key via integer(forKey:).
            refreshInterval = .fiveMinutes
        }
        showRemaining = defaults.object(forKey: "showRemaining") as? Bool ?? false
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        outOfManaAlert = defaults.object(forKey: "outOfManaAlert") as? Bool ?? true
    }

    /// Unknown or missing persisted values fall back per provider to
    /// `.session` without resetting other valid settings.
    func menuBarDisplay(for provider: ProviderID) -> MenuBarDisplay {
        menuBarMetric[provider] ?? .session
    }

    func setMenuBarDisplay(_ display: MenuBarDisplay, for provider: ProviderID) {
        menuBarMetric[provider] = display
    }
}
