import Foundation

/// Codex (ChatGPT) usage: GET chatgpt.com/backend-api/wham/usage.
///
/// Contract (adapted from burakgon/ai-usage-menubar / OpenUsage, MIT — see NOTICE):
/// - headers: Bearer token, ChatGPT-Account-Id when an account id is present
/// - rate_limit.primary_window / secondary_window: used_percent (0–100),
///   limit_window_seconds (18000 = 5h session, 604800 = weekly), reset_at (epoch s)
/// - plan_type: "pro" → Pro 20x, "prolite" → Pro 5x
/// - credits.balance floored to whole credits ($0.04 each)
/// - rate_limit_reset_credits.available_count: banked "usage limit reset" credits;
///   applicable_available_count is the subset redeemable right now (absent → all).
///   When the count is non-zero, GET wham/rate-limit-reset-credits lists each
///   credit's expires_at so we can show the earliest expiry.
struct CodexProvider: UsageProvider {
    let id = ProviderID.codex

    private struct Response: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Int?
            let resetAt: TimeInterval?
        }
        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }
        struct ResetCredits: Decodable {
            let availableCount: Int?
            let applicableAvailableCount: Int?
        }
        struct Credits: Decodable {
            let balance: Double?
            let hasCredits: Bool?

            enum CodingKeys: String, CodingKey { case balance, hasCredits }

            // balance arrives as a string ("0") on some plans, a number on others.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let string = try? container.decode(String.self, forKey: .balance) {
                    balance = Double(string)
                } else {
                    balance = try? container.decode(Double.self, forKey: .balance)
                }
                hasCredits = try? container.decode(Bool.self, forKey: .hasCredits)
            }
        }
        let rateLimit: RateLimit?
        let planType: String?
        let credits: Credits?
        let rateLimitResetCredits: ResetCredits?
    }

    /// GET wham/rate-limit-reset-credits — the per-credit detail list.
    private struct ResetCreditsResponse: Decodable {
        struct Credit: Decodable {
            let status: String?
            let expiresAt: String?
        }
        let credits: [Credit]?
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        do {
            return try await fetch(forceRefresh: false)
        } catch HTTPError.badStatus(let code) where code == 401 || code == 403 {
            return try await fetch(forceRefresh: true)
        } catch {
            throw mapError(error, provider: id.displayName)
        }
    }

    private func fetch(forceRefresh: Bool) async throws -> ProviderSnapshot {
        let (tokens, _) = try await CodexCredentialStore.shared.validTokens(forceRefresh: forceRefresh)
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw ProviderFailure.transient("Invalid Codex usage URL.")
        }
        let request = authorizedRequest(url: url, tokens: tokens)

        let (data, _) = try await HTTPClient.shared.send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        var metrics: [QuotaMetric] = []
        for window in [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow] {
            guard let window, let percent = window.usedPercent else { continue }
            let seconds = window.limitWindowSeconds ?? 0
            let kind: MetricKind? = seconds == 18_000 ? .session : seconds == 604_800 ? .weekly : nil
            let title = seconds == 18_000 ? "5h limit" : seconds == 604_800 ? "Weekly limit" : "Limit (\(seconds / 3600)h)"
            metrics.append(QuotaMetric(
                id: "codex.\(seconds)", kind: kind, title: title,
                usedRatio: min(max(percent / 100, 0), 1),
                resetDate: DateParsing.parse(epochSeconds: window.resetAt)))
        }
        guard !metrics.isEmpty else {
            throw ProviderFailure.transient("Codex usage response had no rate-limit windows.")
        }

        var extras: [ExtraInfo] = []
        if let credits = response.credits, credits.hasCredits == true, let balance = credits.balance {
            let whole = balance.rounded(.down)
            extras.append(ExtraInfo(
                id: "codex.credits", label: "Flex credits",
                value: String(format: "%.0f (≈$%.2f)", whole, whole * 0.04)))
        }
        if let resets = response.rateLimitResetCredits,
           let available = resets.availableCount, available > 0 {
            var value = "\(available)"
            if let applicable = resets.applicableAvailableCount, applicable > 0 {
                value += " · \(applicable) usable"
            }
            if let expiry = await nextResetExpiry(tokens: tokens) {
                value += " · exp \(expiry.formatted(.dateTime.month(.abbreviated).day()))"
            }
            extras.append(ExtraInfo(id: "codex.resets", label: "Limit resets", value: value))
        }

        return ProviderSnapshot(
            providerID: id,
            planName: Self.planName(response.planType),
            metrics: metrics, extras: extras, fetchedAt: Date())
    }

    private func authorizedRequest(url: URL, tokens: CodexCredentialStore.Tokens) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ManaBar/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountId, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    /// Earliest expiry among redeemable reset credits; nil when the detail
    /// endpoint fails or lists none — the banked count is still shown.
    private func nextResetExpiry(tokens: CodexCredentialStore.Tokens) async -> Date? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits") else {
            return nil
        }
        guard let (data, _) = try? await HTTPClient.shared.send(authorizedRequest(url: url, tokens: tokens)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let detail = try? decoder.decode(ResetCreditsResponse.self, from: data) else { return nil }
        return (detail.credits ?? [])
            .filter { $0.status == "available" }
            .compactMap { $0.expiresAt.flatMap(DateParsing.parse) }
            .min()
    }

    private static func planName(_ planType: String?) -> String? {
        switch planType {
        case "pro": "Pro 20x"
        case "prolite": "Pro 5x"
        case .some(let other): other.prefix(1).uppercased() + other.dropFirst()
        case nil: nil
        }
    }
}
