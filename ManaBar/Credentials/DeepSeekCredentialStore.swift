import Foundation

/// DeepSeek API key, pasted once in Settings and kept in the Keychain.
/// Unlike the CLI-backed stores there is nothing to refresh — the key is
/// used as-is on every request.
actor DeepSeekCredentialStore {
    static let shared = DeepSeekCredentialStore()

    private var cached: String?

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
    }

    func clear() {
        cached = nil
        KeychainHelper.delete(
            service: KeychainHelper.deepseekService,
            account: KeychainHelper.deepseekAccount)
    }

    /// Throws `notConfigured` when no key is stored.
    func apiKey() throws -> String {
        if let cached { return cached }
        if let loaded = load() {
            cached = loaded
            return loaded
        }
        throw ProviderFailure.notConfigured(
            "DeepSeek API key not set — add it in Settings.")
    }

    private func load() -> String? {
        guard let raw = KeychainHelper.read(
            service: KeychainHelper.deepseekService,
            account: KeychainHelper.deepseekAccount),
            !raw.isEmpty else { return nil }
        return raw
    }
}
