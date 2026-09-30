import Foundation

/// Reads and refreshes Codex (ChatGPT OAuth) credentials from auth.json.
///
/// Contract (adapted from burakgon/ai-usage-menubar / OpenUsage, MIT — see NOTICE):
/// - lookup order: $CODEX_HOME/auth.json → ~/.config/codex/auth.json → ~/.codex/auth.json
/// - expiry comes from the access token's JWT `exp` claim with a 5-minute leeway;
///   only if the JWT can't be decoded, fall back to `last_refresh` older than 8 days
/// - before refreshing, re-read the file to adopt tokens the Codex CLI rotated
/// - refresh: POST auth.openai.com/oauth/token, form-encoded,
///   client_id app_EMoamEEZ73f0CkXaXp7hrann
actor CodexCredentialStore {
    static let shared = CodexCredentialStore()

    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var accountId: String?
    }

    private struct AuthFile: Codable {
        var tokens: Tokens?
        var lastRefresh: String?
        var apiKey: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case lastRefresh = "last_refresh"
            case apiKey = "OPENAI_API_KEY"
        }
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
    }

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let refreshLeeway: TimeInterval = 5 * 60
    private static let lastRefreshMaxAge: TimeInterval = 8 * 24 * 60 * 60

    private var authFileURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            candidates.append(URL(fileURLWithPath: codexHome).appending(path: "auth.json"))
        }
        candidates.append(home.appending(path: ".config/codex/auth.json"))
        candidates.append(home.appending(path: ".codex/auth.json"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path()) }
    }

    /// Returns a valid (accessToken, accountID) pair, refreshing when needed.
    func validTokens(forceRefresh: Bool = false) async throws -> (Tokens, URL) {
        guard let url = authFileURL else {
            throw ProviderFailure.notConfigured("Codex auth.json not found — log in with the codex CLI first.")
        }
        let auth = try read(url)
        guard let tokens = auth.tokens else {
            if auth.apiKey != nil {
                throw ProviderFailure.notConfigured("Codex is using an API key — usage is only available for ChatGPT sign-in.")
            }
            throw ProviderFailure.notConfigured("Codex auth.json has no tokens — log in with the codex CLI first.")
        }
        guard forceRefresh || needsRefresh(tokens, lastRefresh: auth.lastRefresh) else {
            return (tokens, url)
        }
        return (try await refresh(tokens, url: url), url)
    }

    // MARK: - Private

    private func read(_ url: URL) throws -> AuthFile {
        guard let data = FileManager.default.contents(atPath: url.path()) else {
            throw ProviderFailure.transient("Could not read Codex auth.json.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let auth = try? decoder.decode(AuthFile.self, from: data) else {
            throw ProviderFailure.transient("Could not parse Codex auth.json.")
        }
        return auth
    }

    private func needsRefresh(_ tokens: Tokens, lastRefresh: String?) -> Bool {
        if let expiry = Self.jwtExpiry(tokens.accessToken) {
            return expiry <= Date().addingTimeInterval(Self.refreshLeeway)
        }
        // Fallback only when the JWT can't be decoded.
        guard let lastRefresh, let date = DateParsing.parse(lastRefresh) else { return true }
        return Date().timeIntervalSince(date) > Self.lastRefreshMaxAge
    }

    private func refresh(_ tokens: Tokens, url: URL) async throws -> Tokens {
        // Adopt CLI-rotated tokens if the file changed since we read it.
        if let current = try? read(url).tokens,
           current.accessToken != tokens.accessToken,
           let expiry = Self.jwtExpiry(current.accessToken),
           expiry > Date().addingTimeInterval(Self.refreshLeeway) {
            return current
        }

        guard let refreshToken = tokens.refreshToken else {
            throw ProviderFailure.authExpired("Codex has no refresh token — re-run codex login.")
        }
        guard let endpoint = URL(string: "https://auth.openai.com/oauth/token") else {
            throw ProviderFailure.transient("Invalid Codex auth URL.")
        }
        let request = URLRequest.formPOST(endpoint, fields: [
            ("grant_type", "refresh_token"),
            ("client_id", Self.clientID),
            ("refresh_token", refreshToken),
        ])
        let data: Data
        do {
            (data, _) = try await HTTPClient.shared.send(request)
        } catch HTTPError.badStatus(let code) where code == 400 || code == 401 || code == 403 {
            throw ProviderFailure.authExpired("Codex session expired — re-run codex login.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(RefreshResponse.self, from: data)

        var fresh = tokens
        fresh.accessToken = response.accessToken
        if let rotated = response.refreshToken { fresh.refreshToken = rotated }
        if let idToken = response.idToken { fresh.idToken = idToken }

        // Merge back into the file, preserving unrelated keys (auth_mode, API key, ...).
        if var object = (try? JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: url.path()) ?? Data())) as? [String: Any],
           let onDiskTokens = object["tokens"] as? [String: Any],
           (onDiskTokens["refresh_token"] as? String) == refreshToken || onDiskTokens["refresh_token"] == nil {
            var tokenDict = onDiskTokens
            tokenDict["access_token"] = fresh.accessToken
            if let rotated = fresh.refreshToken { tokenDict["refresh_token"] = rotated }
            if let idToken = fresh.idToken { tokenDict["id_token"] = idToken }
            object["tokens"] = tokenDict
            object["last_refresh"] = ISO8601DateFormatter().string(from: Date())
            if let merged = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                try? writeAtomically(merged, to: url)
            }
        }
        return fresh
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .withoutOverwriting)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tempURL.path())
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    /// base64URL-decodes the JWT payload and reads `exp`. Returns nil on any failure.
    static func jwtExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
