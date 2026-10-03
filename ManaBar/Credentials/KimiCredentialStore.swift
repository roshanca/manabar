import Foundation

/// Reads and refreshes Kimi Coding Plan credentials from
/// ~/.kimi-code/credentials/kimi-code.json.
///
/// Refresh contract (reverse-engineered, verified against the live service):
/// - access tokens live 15 minutes; refresh only when expired or within 60s of expiry
/// - POST auth host /api/oauth/token, form-encoded, client_id 17eb48c098
/// - the response ROTATES refresh_token, so the new pair must be written back
///   atomically; before writing we re-read the file — if kimi CLI refreshed in
///   the meantime (its refresh_token differs from what we sent), we discard our
///   result and adopt the file's newer tokens instead.
actor KimiCredentialStore {
    static let shared = KimiCredentialStore()

    struct Credentials: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: TimeInterval
        var expiresIn: Double?
        var scope: String?
        var tokenType: String?
    }

    enum Region: Sendable {
        case mainland
        case global

        var authHost: String { self == .mainland ? "auth.kimi.com" : "auth.kimi.ai" }
        var apiHost: String { self == .mainland ? "api.kimi.com" : "api.kimi.ai" }
        /// kimi.com web app host; authHost also serves the web session gateway.
        var webHost: String { self == .mainland ? "www.kimi.com" : "www.kimi.ai" }
    }

    private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private static let expiryLeeway: TimeInterval = 60

    private var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".kimi-code/credentials/kimi-code.json")
    }
    private var regionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".kimi-code/region")
    }

    func currentRegion() -> Region {
        guard let raw = try? String(contentsOf: regionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return .mainland }
        return raw.hasPrefix("global") ? .global : .mainland
    }

    func validCredentials(forceRefresh: Bool = false) async throws -> Credentials {
        let current = try read()
        let expiring = current.expiresAt <= Date().timeIntervalSince1970 + Self.expiryLeeway
        guard forceRefresh || expiring else { return current }
        return try await refresh(current)
    }

    // MARK: - Private

    private func read() throws -> Credentials {
        guard let data = FileManager.default.contents(atPath: credentialsURL.path()) else {
            throw ProviderFailure.notConfigured("Kimi credentials not found — log in with the kimi CLI first.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let credentials = try? decoder.decode(Credentials.self, from: data) else {
            throw ProviderFailure.transient("Could not parse Kimi credentials file.")
        }
        return credentials
    }

    private func refresh(_ credentials: Credentials) async throws -> Credentials {
        let region = currentRegion()
        guard let url = URL(string: "https://\(region.authHost)/api/oauth/token") else {
            throw ProviderFailure.transient("Invalid Kimi auth URL.")
        }
        let request = URLRequest.formPOST(url, fields: [
            ("grant_type", "refresh_token"),
            ("client_id", Self.clientID),
            ("refresh_token", credentials.refreshToken),
        ])
        let data: Data
        do {
            (data, _) = try await HTTPClient.shared.send(request)
        } catch HTTPError.badStatus(let code) where code == 400 || code == 401 {
            throw ProviderFailure.authExpired("Kimi session expired — re-run kimi CLI login.")
        }

        // The refresh response carries only expires_in (no expires_at) and
        // rotates refresh_token; compute the absolute expiry ourselves.
        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: TimeInterval?
            let scope: String?
            let tokenType: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(RefreshResponse.self, from: data)
        let fresh = Credentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credentials.refreshToken,
            expiresAt: Date().timeIntervalSince1970 + (response.expiresIn ?? 900),
            expiresIn: response.expiresIn,
            scope: response.scope ?? credentials.scope,
            tokenType: response.tokenType ?? credentials.tokenType)

        // Race check: if the CLI rotated tokens while we were refreshing, adopt the file's.
        if let onDisk = try? read(), onDisk.refreshToken != credentials.refreshToken {
            return onDisk
        }

        try writeAtomically(fresh)
        return fresh
    }

    /// Atomic write via temp file + rename in the same directory, keeping 0600.
    private func writeAtomically(_ credentials: Credentials) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        let tempURL = credentialsURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .withoutOverwriting)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tempURL.path())
        _ = try FileManager.default.replaceItemAt(credentialsURL, withItemAt: tempURL)
    }
}
