import Foundation

/// DeepSeek API key, pasted once in Settings and kept in the Keychain.
/// Unlike the CLI-backed stores there is nothing to refresh — the key is
/// used as-is on every request.
///
/// A generation counter (UserDefaults `deepseekKeyGeneration`) is bumped on
/// every save/clear and spend history is reset, so a different wallet never
/// inherits the old one's spend baseline — including an in-flight refresh
/// that fetched with the previous key.
actor DeepSeekCredentialStore {
    static let shared = DeepSeekCredentialStore()

    private static let generationKey = "deepseekKeyGeneration"

    private var cached: String?

    /// Current key generation; 0 for a key that was never (re)saved.
    private var generation: Int {
        UserDefaults.standard.integer(forKey: Self.generationKey)
    }

    var isConfigured: Bool {
        cached != nil || load() != nil
    }

    func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        cached = trimmed
        KeychainHelper.save(
            service: KeychainHelper.deepseekService,
            account: KeychainHelper.deepseekAccount,
            value: trimmed)
        bumpGeneration()
    }

    func clear() {
        cached = nil
        KeychainHelper.delete(
            service: KeychainHelper.deepseekService,
            account: KeychainHelper.deepseekAccount)
        bumpGeneration()
    }

    /// Returns the key plus the generation it was read under — pass the
    /// generation to `trackSpend` so a fetch that started before a key
    /// change can't write spend history for the old wallet.
    func apiKey() throws -> (key: String, generation: Int) {
        let current = generation
        if let cached { return (cached, current) }
        if let loaded = load() {
            cached = loaded
            return (loaded, current)
        }
        throw ProviderFailure.notConfigured(
            "DeepSeek API key not set — add it in Settings.")
    }

    /// Runs the spend tracker over freshly fetched balances — but only when
    /// `generation` is still current. Serialized with save/clear by the
    /// actor, so no race.
    func trackSpend(_ balances: [WalletBalance], generation: Int) -> [WalletBalance] {
        guard generation == self.generation else { return balances }
        return balances.map { balance in
            var balance = balance
            balance.todaySpent = DeepSeekSpendTracker.todaySpent(
                currency: balance.currency, total: balance.total)
            return balance
        }
    }

    // MARK: - Private

    private func bumpGeneration() {
        UserDefaults.standard.set(generation + 1, forKey: Self.generationKey)
        DeepSeekSpendTracker.reset()
    }

    private func load() -> String? {
        guard let raw = KeychainHelper.read(
            service: KeychainHelper.deepseekService,
            account: KeychainHelper.deepseekAccount),
            !raw.isEmpty else { return nil }
        return raw
    }
}
