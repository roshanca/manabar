import Foundation

/// Claude Code subscription usage: GET api.anthropic.com/api/oauth/usage.
///
/// Contract (adapted from burakgon/ai-usage-menubar / OpenUsage, MIT — see NOTICE):
/// - headers: Bearer token, anthropic-beta: oauth-2025-04-20, claude-code UA
/// - windows: five_hour / seven_day / seven_day_sonnet, each with
///   `utilization` (a 0–100 percentage) and `resets_at`
/// - `limits[]` carries model-scoped weekly limits (scope.model.display_name)
/// - `extra_usage` values are integer US cents despite the "credits" name
struct ClaudeCodeProvider: UsageProvider {
    let id = ProviderID.claudeCode

    private struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey { case utilization, resetsAt }

            // resets_at may be an ISO-8601 string or an epoch number.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                utilization = try? container.decode(Double.self, forKey: .utilization)
                if let string = try? container.decode(String.self, forKey: .resetsAt) {
                    resetsAt = string
                } else if let epoch = try? container.decode(Double.self, forKey: .resetsAt) {
                    resetsAt = String(epoch)
                } else {
                    resetsAt = nil
                }
            }
        }
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let displayName: String? }
                let model: Model?
            }
            let kind: String?
            let scope: Scope?
            let percent: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey { case kind, scope, percent, resetsAt }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try? container.decode(String.self, forKey: .kind)
                scope = try? container.decode(Scope.self, forKey: .scope)
                percent = try? container.decode(Double.self, forKey: .percent)
                if let string = try? container.decode(String.self, forKey: .resetsAt) {
                    resetsAt = string
                } else if let epoch = try? container.decode(Double.self, forKey: .resetsAt) {
                    resetsAt = String(epoch)
                } else {
                    resetsAt = nil
                }
            }
        }
        struct ExtraUsage: Decodable {
            let isEnabled: Bool?
            let usedCredits: Double?
            let monthlyLimit: Double?
        }
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDaySonnet: Window?
        let limits: [Limit]?
        let extraUsage: ExtraUsage?
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
        let oauth = try await ClaudeAuthStore.shared.validTokens(forceRefresh: forceRefresh)
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ProviderFailure.transient("Invalid Claude usage URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await HTTPClient.shared.send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        var metrics: [QuotaMetric] = []
        func append(_ window: Response.Window?, id metricID: String, kind: MetricKind, title: String) {
            guard let utilization = window?.utilization else { return }
            metrics.append(QuotaMetric(
                id: metricID, kind: kind, title: title,
                usedRatio: min(max(utilization / 100, 0), 1),
                resetDate: window?.resetsAt.flatMap(DateParsing.parse),
                windowSeconds: kind.defaultWindowSeconds))
        }
        append(response.fiveHour, id: "claude.5h", kind: .session, title: "5h limit")
        append(response.sevenDay, id: "claude.7d", kind: .weekly, title: "Weekly limit")
        append(response.sevenDaySonnet, id: "claude.sonnet", kind: .weekly, title: "Sonnet weekly")

        for limit in response.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let percent = limit.percent,
                  let name = limit.scope?.model?.displayName else { continue }
            metrics.append(QuotaMetric(
                id: "claude.limit.\(name)", kind: .weekly, title: "\(name) weekly",
                usedRatio: min(max(percent / 100, 0), 1),
                resetDate: limit.resetsAt.flatMap(DateParsing.parse),
                windowSeconds: MetricKind.weekly.defaultWindowSeconds))
        }
        guard !metrics.isEmpty else {
            throw ProviderFailure.transient("Claude usage response had no quota windows.")
        }

        var extras: [ExtraInfo] = []
        if let extra = response.extraUsage, extra.isEnabled == true,
           let used = extra.usedCredits, let limit = extra.monthlyLimit {
            extras.append(ExtraInfo(
                id: "claude.extra", label: "Extra usage",
                value: String(format: "$%.2f / $%.2f this month", used / 100, limit / 100)))
        }

        return ProviderSnapshot(
            providerID: id,
            planName: Self.planName(subscriptionType: oauth.subscriptionType, rateLimitTier: oauth.rateLimitTier),
            metrics: metrics, extras: extras, fetchedAt: Date())
    }

    /// "max" + "default_claude_max_5x" → "Max 5x".
    private static func planName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        var name = subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
        if let tier = rateLimitTier,
           let range = tier.range(of: #"\d+x"#, options: .regularExpression) {
            name += " " + tier[range]
        }
        return name
    }
}
