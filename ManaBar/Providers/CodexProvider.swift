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
///   credit's expires_at; the popover shows them and can spend one
///   (see CodexResetClaimService).
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
        struct ResetCreditCounts: Decodable {
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
        let rateLimitResetCredits: ResetCreditCounts?
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
                resetDate: DateParsing.parse(epochSeconds: window.resetAt),
                windowSeconds: window.limitWindowSeconds.map(TimeInterval.init)))
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
        var resets: ResetCredits?
        if let banked = response.rateLimitResetCredits,
           let available = banked.availableCount, available > 0 {
            // Best-effort like the old extra row: the count still shows when
            // the detail endpoint fails.
            let expiries = (try? await CodexResetClaimService.creditExpiries(tokens: tokens)) ?? []
            resets = ResetCredits(count: available,
                                  usableNow: banked.applicableAvailableCount,
                                  expiries: expiries)
        }

        return ProviderSnapshot(
            providerID: id,
            planName: Self.planName(response.planType),
            metrics: metrics, extras: extras, fetchedAt: Date(), resets: resets)
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

    private static func planName(_ planType: String?) -> String? {
        switch planType {
        case "pro": "Pro 20x"
        case "prolite": "Pro 5x"
        case .some(let other): other.prefix(1).uppercased() + other.dropFirst()
        case nil: nil
        }
    }
}
