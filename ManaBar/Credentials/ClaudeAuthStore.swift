import Foundation

/// Reads Claude Code OAuth credentials from the macOS keychain (service
/// "Claude Code-credentials") and refreshes them when near expiry.
///
/// Contract (adapted from burakgon/ai-usage-menubar / OpenUsage, MIT — see NOTICE):
/// - lookup: keychain item for account $USER → service-only item →
///   ~/.claude/.credentials.json (honors CLAUDE_CONFIG_DIR)
/// - JSON shape: top-level "claudeAiOauth" with accessToken / refreshToken /
///   expiresAt (epoch ms) / subscriptionType / rateLimitTier / scopes
/// - scope gate: if scopes are present they must include "user:profile";
///   CLAUDE_CODE_OAUTH_TOKEN is deliberately ignored (lacks that scope)
/// - refresh: POST platform.claude.com/v1/oauth/token (JSON body),
///   client_id 9d1c250a-e61b-44d9-88ed-5944d1962f5e
actor ClaudeAuthStore {
    static let shared = ClaudeAuthStore()

    struct OAuth: Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var subscriptionType: String?
        var rateLimitTier: String?
        var scopes: [String]?
    }

    /// Where the credentials came from — determines where refreshed tokens are written back.
    private enum Source {
        case keychain(account: String?)
        case file(URL)
    }

    private static let keychainService = "Claude Code-credentials"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let requiredScope = "user:profile"
    private static let refreshScope = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    private static let refreshLeeway: TimeInterval = 5 * 60

    func validTokens(forceRefresh: Bool = false) async throws -> OAuth {
        let (oauth, source) = try read()
        if let scopes = oauth.scopes, !scopes.isEmpty, !scopes.contains(Self.requiredScope) {
            throw ProviderFailure.authExpired("Claude Code token lacks the user:profile scope — re-run claude login.")
        }
        let expiring = oauth.expiresAt.map { $0 <= Date().addingTimeInterval(Self.refreshLeeway) } ?? false
        guard forceRefresh || expiring else { return oauth }
        return try await refresh(oauth, source: source)
    }

    // MARK: - Read

    private func read() throws -> (OAuth, Source) {
        let account = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        if let json = SecurityCLI.findGenericPassword(service: Self.keychainService, account: account),
           let oauth = Self.parse(json) {
            return (oauth, .keychain(account: account))
        }
        if let json = SecurityCLI.findGenericPassword(service: Self.keychainService, account: nil),
           let oauth = Self.parse(json) {
            return (oauth, .keychain(account: nil))
        }
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        let credentialsFile = configDir.appending(path: ".credentials.json")
        if let data = FileManager.default.contents(atPath: credentialsFile.path()),
           let json = String(data: data, encoding: .utf8),
           let oauth = Self.parse(json) {
            return (oauth, .file(credentialsFile))
        }
        // A gateway setup (ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL) has no
        // claude.ai subscription attached — say so instead of a generic error.
        if let settingsData = FileManager.default.contents(atPath: configDir.appending(path: "settings.json").path()),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let env = settings["env"] as? [String: Any],
           env["ANTHROPIC_AUTH_TOKEN"] is String || env["ANTHROPIC_BASE_URL"] is String {
            throw ProviderFailure.notConfigured("Claude Code uses a custom gateway (ANTHROPIC_BASE_URL) — subscription usage is only available with claude.ai sign-in.")
        }
        throw ProviderFailure.notConfigured("Claude Code credentials not found — log in with the claude CLI first.")
    }

    private static func parse(_ json: String) -> OAuth? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = object["claudeAiOauth"] as? [String: Any],
              let accessToken = container["accessToken"] as? String, !accessToken.isEmpty else { return nil }
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = (container["expiresAt"] as? TimeInterval).map {
            // Claude Code stores epoch milliseconds.
            $0 > 1e12 ? Date(timeIntervalSince1970: $0 / 1000) : Date(timeIntervalSince1970: $0)
        }
        return OAuth(
            accessToken: trimmed,
            refreshToken: container["refreshToken"] as? String,
            expiresAt: expiresAt,
            subscriptionType: container["subscriptionType"] as? String,
            rateLimitTier: container["rateLimitTier"] as? String,
            scopes: container["scopes"] as? [String]
        )
    }

    // MARK: - Refresh

    private func refresh(_ oauth: OAuth, source: Source) async throws -> OAuth {
        guard let refreshToken = oauth.refreshToken else {
            throw ProviderFailure.authExpired("Claude Code session expired — re-run claude login.")
        }
        guard let url = URL(string: "https://platform.claude.com/v1/oauth/token") else {
            throw ProviderFailure.transient("Invalid Claude auth URL.")
        }
        let request = try URLRequest.jsonPOST(url, body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.refreshScope,
        ])
        let data: Data
        do {
            (data, _) = try await HTTPClient.shared.send(request)
        } catch HTTPError.badStatus(let code) where code == 400 || code == 401 || code == 403 {
            throw ProviderFailure.authExpired("Claude Code session expired — re-run claude login.")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = object["access_token"] as? String else {
            throw ProviderFailure.transient("Could not parse Claude token refresh response.")
        }
        var fresh = oauth
        fresh.accessToken = newAccess.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rotated = object["refresh_token"] as? String { fresh.refreshToken = rotated }
        if let expiresIn = object["expires_in"] as? TimeInterval {
            fresh.expiresAt = Date().addingTimeInterval(expiresIn)
        }

        // Best-effort write-back so the CLI sees the rotated tokens too.
        writeBack(fresh, source: source)
        return fresh
    }

    private func writeBack(_ oauth: OAuth, source: Source) {
        var container: [String: Any] = ["accessToken": oauth.accessToken]
        if let refreshToken = oauth.refreshToken { container["refreshToken"] = refreshToken }
        if let expiresAt = oauth.expiresAt { container["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000) }
        if let subscriptionType = oauth.subscriptionType { container["subscriptionType"] = subscriptionType }
        if let rateLimitTier = oauth.rateLimitTier { container["rateLimitTier"] = rateLimitTier }
        if let scopes = oauth.scopes { container["scopes"] = scopes }

        switch source {
        case .keychain(let account):
            // Preserve any sibling keys next to claudeAiOauth.
            var object: [String: Any] = [:]
            if let existing = SecurityCLI.findGenericPassword(service: Self.keychainService, account: account),
               let data = existing.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object = parsed
            }
            object["claudeAiOauth"] = container
            guard let merged = try? JSONSerialization.data(withJSONObject: object),
                  let string = String(data: merged, encoding: .utf8) else { return }
            SecurityCLI.setGenericPassword(service: Self.keychainService, account: account, value: string)
        case .file(let url):
            var object: [String: Any] = [:]
            if let data = FileManager.default.contents(atPath: url.path()),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object = parsed
            }
            object["claudeAiOauth"] = container
            guard let merged = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
            let tempURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
            try? merged.write(to: tempURL, options: .withoutOverwriting)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path())
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        }
    }
}
