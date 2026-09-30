import Foundation
import OSLog

private let logger = Logger(subsystem: "com.roshan.manabar", category: "refresh")

/// Global app state: latest snapshot per provider, refresh cadence, staleness.
/// Zero CPU between refreshes — the cadence is a sleeping Task.
@MainActor @Observable
final class AppState {
    let settings = AppSettings.shared

    private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    /// Per-provider failure messages; a provider with a failure keeps its last
    /// good snapshot and renders stale.
    private(set) var failures: [ProviderID: String] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private var cadenceTask: Task<Void, Never>?

    func startCadence() {
        guard cadenceTask == nil else { return }
        cadenceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.settings.refreshInterval.seconds ?? 0
                guard interval > 0 else { return } // manual mode: refresh once, then idle
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Call after the refresh interval changes so the new cadence takes effect.
    func restartCadence() {
        cadenceTask?.cancel()
        cadenceTask = nil
        startCadence()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }

        let enabled = settings.enabledProviders
        let providers: [any UsageProvider] = [
            KimiProvider(), ClaudeCodeProvider(), CodexProvider(), DevinProvider(),
        ].filter { enabled.contains($0.id) }

        await withTaskGroup(of: (ProviderID, ProviderSnapshot?, String?).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let snapshot = try await provider.fetchUsage()
                        return (provider.id, snapshot, nil)
                    } catch {
                        let message = (error as? ProviderFailure)?.userMessage
                            ?? "\(provider.id.displayName) could not be refreshed."
                        return (provider.id, nil, message)
                    }
                }
            }
            for await (id, snapshot, failure) in group {
                if let snapshot {
                    snapshots[id] = snapshot
                    failures[id] = nil
                    logger.info("\(id.rawValue): ok, \(snapshot.metrics.count) metrics")
                } else {
                    failures[id] = failure
                    // Failure messages are provider-sanitized; never log raw errors (may contain credentials).
                    logger.error("\(id.rawValue): \(failure ?? "unknown", privacy: .public)")
                }
            }
        }
    }

    // MARK: - Menu bar state

    /// Fill ratio for the mana bar: the configured metric of the primary provider.
    var menuBarRatio: Double? {
        guard let snapshot = snapshots[settings.primaryProvider] else { return nil }
        let kind = settings.menuBarKind(for: settings.primaryProvider)
        return snapshot.metrics.first(where: { $0.kind == kind })?.usedRatio
            ?? snapshot.metrics.first?.usedRatio
    }

    func isStale(_ provider: ProviderID) -> Bool {
        failures[provider] != nil
    }

    func failureMessage(_ provider: ProviderID) -> String? {
        failures[provider]
    }
}
