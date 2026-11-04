import Foundation

/// Spends Codex "usage limit reset" credits from the popover.
///
/// Contract (adapted from OpenUsage, MIT — see NOTICE):
/// - GET  chatgpt.com/backend-api/wham/rate-limit-reset-credits →
///   {credits: [{id, status, expires_at}], available_count}
/// - POST …/rate-limit-reset-credits/consume, body {credit_id, redeem_request_id}
///   `redeem_request_id` is a client-minted UUID idempotency key — retrying
///   the same key never double-spends; the server replays `already_redeemed`.
/// - The consume answer comes back HTTP 200 with the outcome in body.code:
///   "reset"/"already_redeemed" → success, "nothing_to_reset" and "no_credit"
///   are no-ops surfaced to the user, anything else → refused.
/// - Both calls send `OpenAI-Beta: codex-1` + `originator: Codex Desktop`,
///   which the endpoints expect (they mirror the Codex desktop client).
actor CodexResetClaimService {
    static let shared = CodexResetClaimService()

    enum Outcome: Sendable, Equatable {
        /// `reset`, or `already_redeemed` — the idempotency key absorbing a
        /// retry of a claim that already landed, so it counts as success.
        case success
        /// `nothing_to_reset` — the current limits don't need a reset.
        case nothingToReset
        /// `no_credit`, or no available credit was left to pick.
        case noCredit
        /// 401/403 persisted across a token refresh — re-login needed.
        case authExpired
        /// Transport errors, 5xx, unparseable or unknown codes.
        case failed(String)
    }

    /// One credit from the list endpoint.
    struct Credit: Decodable, Sendable {
        let id: String?
        let status: String?
        /// Raw `expires_at` — an ISO-8601 string on known plans, but tolerate
        /// epoch numbers so a shape change doesn't break parsing.
        let expiresAt: String?

        enum CodingKeys: String, CodingKey { case id, status, expiresAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(String.self, forKey: .id)
            status = try? container.decode(String.self, forKey: .status)
            if let string = try? container.decode(String.self, forKey: .expiresAt) {
                expiresAt = string
            } else if let epoch = try? container.decode(Double.self, forKey: .expiresAt) {
                expiresAt = String(epoch)
            } else {
                expiresAt = nil
            }
        }

        var expiry: Date? { expiresAt.flatMap(DateParsing.parse) }
        var isAvailable: Bool { status == nil || status == "available" }
    }

    private struct ListResponse: Decodable {
        let credits: [Credit]?
    }

    /// requestID → creditID for claims in flight. A retry of a key that
    /// already matched replays the same (key, credit) pair instead of matching
    /// again: after a consume whose answer was lost, the credit is gone from
    /// the list, and only the replay lets `already_redeemed` prove it landed.
    private var matchedCreditIDs: [String: String] = [:]

    /// Expiries of the available credits, earliest first — the display pass's
    /// read of the same list the claim flow matches against.
    static func creditExpiries(tokens: CodexCredentialStore.Tokens) async throws -> [Date] {
        try await list(tokens: tokens)
            .filter(\.isAvailable)
            .compactMap(\.expiry)
            .sorted()
    }

    /// Re-fetches the credit list at claim time, spends the earliest-expiring
    /// available credit, and maps the consume code to an outcome.
    func claim(redeemRequestID: String) async -> Outcome {
        var tokens: CodexCredentialStore.Tokens
        do {
            (tokens, _) = try await CodexCredentialStore.shared.validTokens()
        } catch let failure as ProviderFailure {
            return mapFailure(failure)
        } catch {
            return .failed("Codex sign-in could not be read.")
        }

        let creditID: String
        if let matched = matchedCreditIDs[redeemRequestID] {
            creditID = matched
        } else {
            let credits: [Credit]
            do {
                (credits, tokens) = try await withAuthRetry(tokens: tokens) { tokens in
                    try await Self.list(tokens: tokens)
                }
            } catch let failure as ProviderFailure {
                return mapFailure(failure)
            } catch HTTPError.badStatus(let code) {
                return .failed("ChatGPT refused the request (HTTP \(code)).")
            } catch {
                return .failed("Could not reach ChatGPT.")
            }
            // Soonest expiry first; undated credits sort last.
            guard let pick = credits.filter(\.isAvailable)
                    .min(by: { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }),
                  let id = pick.id else {
                return .noCredit
            }
            matchedCreditIDs[redeemRequestID] = id
            creditID = id
        }

        do {
            let (outcome, _) = try await withAuthRetry(tokens: tokens) { tokens in
                try await Self.consume(tokens: tokens, creditID: creditID, redeemRequestID: redeemRequestID)
            }
            // Terminal answer — the key is spent; a fresh claim mints a new one.
            matchedCreditIDs[redeemRequestID] = nil
            return outcome
        } catch let failure as ProviderFailure {
            return mapFailure(failure)
        } catch HTTPError.badStatus(let code) {
            return .failed("ChatGPT refused the request (HTTP \(code)).")
        } catch {
            // The answer may have been lost — keep the matched pair so a retry
            // with the same requestID replays it and learns via already_redeemed.
            return .failed("Could not reach ChatGPT.")
        }
    }

    // MARK: - Endpoints

    private static let listURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    private static let consumeURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!

    private static func list(tokens: CodexCredentialStore.Tokens) async throws -> [Credit] {
        let (data, _) = try await HTTPClient.shared.send(authorizedRequest(url: listURL, tokens: tokens))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ListResponse.self, from: data).credits ?? []
    }

    private static func consume(tokens: CodexCredentialStore.Tokens, creditID: String, redeemRequestID: String) async throws -> Outcome {
        var request = authorizedRequest(url: consumeURL, tokens: tokens)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["credit_id": creditID, "redeem_request_id": redeemRequestID],
            options: [.sortedKeys])
        let (data, _) = try await HTTPClient.shared.send(request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = body["code"] as? String else {
            throw ProviderFailure.transient("Codex reset returned an unrecognized response.")
        }
        switch code {
        case "reset", "already_redeemed": return .success
        case "nothing_to_reset": return .nothingToReset
        case "no_credit": return .noCredit
        default: throw ProviderFailure.transient("Codex refused the reset (\(code)).")
        }
    }

    private static func authorizedRequest(url: URL, tokens: CodexCredentialStore.Tokens) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("ManaBar/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountId, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    /// Runs `call`, retrying once with refreshed tokens on 401/403 — the same
    /// dance the usage fetch does. A repeated auth rejection maps to
    /// authExpired; the retried tokens are handed back so the consume call
    /// reuses them.
    private func withAuthRetry<T>(
        tokens: CodexCredentialStore.Tokens,
        _ call: (CodexCredentialStore.Tokens) async throws -> T
    ) async throws -> (T, CodexCredentialStore.Tokens) {
        do {
            return (try await call(tokens), tokens)
        } catch HTTPError.badStatus(let code) where code == 401 || code == 403 {
            let (fresh, _) = try await CodexCredentialStore.shared.validTokens(forceRefresh: true)
            do {
                return (try await call(fresh), fresh)
            } catch HTTPError.badStatus(let retryCode) where retryCode == 401 || retryCode == 403 {
                throw ProviderFailure.authExpired("Codex session expired — re-run codex login.")
            }
        }
    }

    private func mapFailure(_ failure: ProviderFailure) -> Outcome {
        switch failure {
        case .authExpired, .notConfigured: return .authExpired
        case .transient(let message): return .failed(message)
        }
    }
}
