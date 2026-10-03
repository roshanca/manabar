import Foundation

/// Kimi *web* session credentials (kimi.com), used to read the real booster
/// wallet (充值余额) via the membership API — the coding OAuth token is rejected
/// there (web sessions are HS512-signed by a different issuer).
///
/// Contract (verified against the live service, 2026-10):
/// - the user pastes the `refresh_token` from kimi.com localStorage once;
///   it lives ~90 days and is NOT single-use, so the browser keeps its own
///   working chain while we hold ours
/// - refresh: POST {auth host}/api/account.gateway.v1.AuthService/RefreshToken
///   with {"refresh_token": "..."} → {"accessToken": "...", "refreshToken": "..."}
///   (Connect RPC: requests accept proto snake_case, responses come back camelCase)
/// - access tokens live ~15 minutes; each refresh rotates refresh_token,
///   so the fresh pair is always written back
/// - the session blob lives in the Keychain, not on disk
actor KimiWebCredentialStore {
    static let shared = KimiWebCredentialStore()

    struct Session: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: TimeInterval
    }

    private static let expiryLeeway: TimeInterval = 60
    /// Observed access-token TTL; the response carries no expires_in,
    /// so we decode the JWT exp and fall back to this.
    private static let fallbackTTL: TimeInterval = 900

    private var cached: Session?

    var isConfigured: Bool {
        cached != nil || load() != nil
    }

    /// Seed a session from a pasted refresh token; the first use refreshes it.
    func importRefreshToken(_ token: String) {
        let session = Session(accessToken: "", refreshToken: token, expiresAt: 0)
        cached = session
        save(session)
    }

    func clear() {
        cached = nil
        KeychainHelper.delete(
            service: KeychainHelper.kimiWebService, account: KeychainHelper.kimiWebAccount)
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session = cached ?? load() else {
            throw ProviderFailure.notConfigured(
                "Kimi web session not set up — paste a refresh token in Settings.")
        }
        cached = session
        if !forceRefresh, !session.accessToken.isEmpty,
           session.expiresAt > Date().timeIntervalSince1970 + Self.expiryLeeway {
            return session.accessToken
        }
        return try await refresh(session)
    }

    // MARK: - Private

    private func refresh(_ session: Session) async throws -> String {
        let region = await KimiCredentialStore.shared.currentRegion()
        guard let url = URL(
            string: "https://\(region.authHost)/api/account.gateway.v1.AuthService/RefreshToken"
        ) else {
            throw ProviderFailure.transient("Invalid Kimi auth URL.")
        }
        let request = try URLRequest.jsonPOST(url, body: ["refresh_token": session.refreshToken])
        let data: Data
        do {
            (data, _) = try await HTTPClient.shared.send(request)
        } catch HTTPError.badStatus(let code) where code == 400 || code == 401 {
            throw ProviderFailure.authExpired(
                "Kimi web session expired — paste a fresh refresh token in Settings.")
        }

        let response = try JSONDecoder().decode(RefreshResponse.self, from: data)
        let fresh = Session(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? session.refreshToken,
            expiresAt: Self.jwtExpiry(response.accessToken)
                ?? Date().timeIntervalSince1970 + Self.fallbackTTL)
        cached = fresh
        save(fresh)
        return fresh.accessToken
    }

    /// Exp claim from a JWT payload, without verifying the signature.
    private static func jwtExpiry(_ token: String) -> TimeInterval? {
        var payload = token.split(separator: ".").dropFirst().first.map(String.init) ?? ""
        payload = payload.replacing("-", with: "+").replacing("_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else { return nil }
        return exp
    }

    private func load() -> Session? {
        guard let raw = KeychainHelper.read(
            service: KeychainHelper.kimiWebService, account: KeychainHelper.kimiWebAccount),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session),
              let raw = String(data: data, encoding: .utf8) else { return }
        KeychainHelper.save(
            service: KeychainHelper.kimiWebService,
            account: KeychainHelper.kimiWebAccount,
            value: raw)
    }

    /// Server emits camelCase (Connect JSON default).
    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
    }
}
