import Foundation

/// Kimi Coding Plan usage.
///
/// Coding API: GET {api host}/coding/v1/usages with the coding OAuth Bearer
/// token. usages.limit_5h / limit_7d carry used_ratio + reset_time;
/// booster_wallet carries a plan-granted booster credit record (face value in
/// `amount`, remainder in `amountLeft`) — NOT the recharge balance.
/// GET {api host}/coding/v1/me with the same token carries the membership
/// tier in `user_level_name` ("Allegretto", ...).
///
/// The real recharge balance (加油包余额) only exists in the web-session API:
/// POST {web host}/apiv2/kimi.gateway.membership.v2.MembershipService/
/// GetSubscriptionStats with a kimi.com web token (see KimiWebCredentialStore).
/// When configured, it also yields the subscription-period usage ratio.
struct KimiProvider: UsageProvider {
    let id = ProviderID.kimi

    private struct Response: Decodable {
        struct Window: Decodable {
            let usedRatio: Double?
            let resetTime: String?

            enum CodingKeys: String, CodingKey {
                case usedRatio = "used_ratio"
                case resetTime = "reset_time"
            }
        }
        struct Usages: Decodable {
            let limit5h: Window?
            let limit7d: Window?

            enum CodingKeys: String, CodingKey {
                case limit5h = "limit_5h"
                case limit7d = "limit_7d"
            }
        }
        struct Money: Decodable {
            let amount: String?
            let amountLeft: String?
            let unit: String?
            let currency: String?
            let priceInCents: Double?

            enum CodingKeys: String, CodingKey {
                case amount, amountLeft, unit, currency, priceInCents
            }

            // priceInCents arrives as a string.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                amount = try? container.decode(String.self, forKey: .amount)
                amountLeft = try? container.decode(String.self, forKey: .amountLeft)
                unit = try? container.decode(String.self, forKey: .unit)
                currency = try? container.decode(String.self, forKey: .currency)
                if let string = try? container.decode(String.self, forKey: .priceInCents) {
                    priceInCents = Double(string)
                } else {
                    priceInCents = try? container.decode(Double.self, forKey: .priceInCents)
                }
            }
        }
        struct BoosterWallet: Decodable {
            let balance: Money?
            let monthlyUsed: Money?
        }
        let usages: Usages?
        let boosterWallet: BoosterWallet?

        enum CodingKeys: String, CodingKey {
            case usages
            case boosterWallet = "booster_wallet"
        }
    }

    /// GetSubscriptionStats response (camelCase; priceInCents is a string).
    private struct StatsResponse: Decodable {
        struct Money: Decodable {
            let currency: String?
            let priceInCents: String?
        }
        struct BoosterWallet: Decodable {
            let moneyLeft: Money?
            let monthlyUsed: Money?
        }
        struct SubscriptionBalance: Decodable {
            let amountUsedRatio: Double?
            let expireTime: String?
        }
        let boosterWallets: [BoosterWallet]?
        let subscriptionBalance: SubscriptionBalance?
    }

    /// /coding/v1/me — only the tier name is decoded.
    private struct MeResponse: Decodable {
        let userLevelName: String?

        enum CodingKeys: String, CodingKey {
            case userLevelName = "user_level_name"
        }
    }

    /// Result of the optional web-session stats call.
    private struct WebStats {
        var metrics: [QuotaMetric] = []
        var extras: [ExtraInfo] = []
        /// True when the web API supplied the real recharge balance, making
        /// the coding API's plan-credit fallback rows redundant.
        var coversBoosterWallet = false
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        do {
            return try await fetch(forceRefresh: false)
        } catch HTTPError.badStatus(let code) where code == 401 || code == 403 {
            // Token rejected despite being unexpired — force one refresh and retry once.
            return try await fetch(forceRefresh: true)
        } catch {
            throw mapError(error, provider: id.displayName)
        }
    }

    private func fetch(forceRefresh: Bool) async throws -> ProviderSnapshot {
        let store = KimiCredentialStore.shared
        let credentials = try await store.validCredentials(forceRefresh: forceRefresh)
        let region = await store.currentRegion()
        guard let url = URL(string: "https://\(region.apiHost)/coding/v1/usages") else {
            throw ProviderFailure.transient("Invalid Kimi API URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await HTTPClient.shared.send(request)
        let response = try JSONDecoder().decode(Response.self, from: data)

        var metrics: [QuotaMetric] = []
        if let window = response.usages?.limit5h, let ratio = window.usedRatio {
            metrics.append(QuotaMetric(
                id: "kimi.5h", kind: .session, title: "5h limit",
                usedRatio: ratio, resetDate: window.resetTime.flatMap(DateParsing.parse),
                windowSeconds: MetricKind.session.defaultWindowSeconds))
        }
        if let window = response.usages?.limit7d, let ratio = window.usedRatio {
            metrics.append(QuotaMetric(
                id: "kimi.7d", kind: .weekly, title: "Weekly limit",
                usedRatio: ratio, resetDate: window.resetTime.flatMap(DateParsing.parse),
                windowSeconds: MetricKind.weekly.defaultWindowSeconds))
        }
        guard !metrics.isEmpty else {
            throw ProviderFailure.transient("Kimi usage response had no quota windows.")
        }

        let web = await fetchWebStats()
        metrics.append(contentsOf: web.metrics)
        var extras = web.extras
        if !web.coversBoosterWallet {
            // Coding-API fallback: the plan-granted booster credit record
            // (its numbers differ from the recharge balance on the web console).
            if let balance = response.boosterWallet?.balance, let formatted = Self.formatMoney(balance) {
                extras.append(ExtraInfo(
                    id: "kimi.boosterCredit", label: "Booster credit left", value: formatted))
            }
            if let monthly = response.boosterWallet?.monthlyUsed, let formatted = Self.formatMoney(monthly) {
                extras.append(ExtraInfo(
                    id: "kimi.boosterMonthly", label: "Booster this month", value: formatted))
            }
        }

        return ProviderSnapshot(
            providerID: id, planName: await fetchPlanName(accessToken: credentials.accessToken, region: region),
            metrics: metrics, extras: extras, fetchedAt: Date())
    }

    /// Membership tier badge ("Allegretto", ...) from /coding/v1/me — best
    /// effort: the same coding token, failures just leave planName nil.
    private func fetchPlanName(accessToken: String, region: KimiCredentialStore.Region) async -> String? {
        guard let url = URL(string: "https://\(region.apiHost)/coding/v1/me") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await HTTPClient.shared.send(request),
              let me = try? JSONDecoder().decode(MeResponse.self, from: data),
              let name = me.userLevelName, !name.isEmpty else { return nil }
        return name
    }

    // MARK: - Web session stats

    /// Reads the real booster wallet via the kimi.com web session. Optional:
    /// unconfigured or transient failures degrade silently to coding-API data.
    private func fetchWebStats() async -> WebStats {
        let store = KimiWebCredentialStore.shared
        guard await store.isConfigured else { return WebStats() }
        do {
            return try await requestStats(forceRefresh: false)
        } catch HTTPError.badStatus(let code) where code == 401 || code == 403 {
            // Access token rejected despite being unexpired — refresh once and retry.
            do {
                return try await requestStats(forceRefresh: true)
            } catch {
                return Self.webFailure(error)
            }
        } catch {
            return Self.webFailure(error)
        }
    }

    private static func webFailure(_ error: Error) -> WebStats {
        var stats = WebStats()
        if let failure = error as? ProviderFailure, case .authExpired = failure {
            stats.extras.append(ExtraInfo(
                id: "kimi.webSession", label: "Booster balance",
                value: "web session expired — update token in Settings"))
        }
        return stats
    }

    private func requestStats(forceRefresh: Bool) async throws -> WebStats {
        let token = try await KimiWebCredentialStore.shared.validAccessToken(forceRefresh: forceRefresh)
        let region = await KimiCredentialStore.shared.currentRegion()
        guard let url = URL(
            string: "https://\(region.webHost)/apiv2/kimi.gateway.membership.v2.MembershipService/GetSubscriptionStats"
        ) else {
            throw ProviderFailure.transient("Invalid Kimi web API URL.")
        }
        let request = try URLRequest.jsonPOST(
            url, body: [:], headers: ["Authorization": "Bearer \(token)"])
        let (data, _) = try await HTTPClient.shared.send(request)
        let response = try JSONDecoder().decode(StatsResponse.self, from: data)

        var stats = WebStats()
        if let wallet = response.boosterWallets?.first {
            if let formatted = Self.formatCents(wallet.moneyLeft) {
                stats.extras.append(ExtraInfo(
                    id: "kimi.booster", label: "Booster balance", value: formatted))
                stats.coversBoosterWallet = true
            }
            if let formatted = Self.formatCents(wallet.monthlyUsed) {
                stats.extras.append(ExtraInfo(
                    id: "kimi.boosterMonthly", label: "Booster this month", value: formatted))
            }
        }
        if let subscription = response.subscriptionBalance, let ratio = subscription.amountUsedRatio {
            stats.metrics.append(QuotaMetric(
                id: "kimi.subscription", kind: nil, title: "Subscription",
                usedRatio: ratio,
                resetDate: subscription.expireTime.flatMap(DateParsing.parse),
                windowSeconds: nil))
        }
        return stats
    }

    private static func formatCents(_ money: StatsResponse.Money?) -> String? {
        guard let cents = money?.priceInCents.flatMap(Double.init) else { return nil }
        return String(format: "%@ %.2f", money?.currency ?? "CNY", cents / 100)
    }

    /// balance carries `amount` (face value) and `amountLeft` (remaining), both
    /// in nano-units (e.g. "2401249900" ≈ ¥2.40); monthlyUsed carries
    /// priceInCents instead.
    private static func formatMoney(_ money: Response.Money) -> String? {
        let currency = money.currency ?? "CNY"
        if let cents = money.priceInCents {
            return String(format: "%@ %.2f", currency, cents / 100)
        }
        guard let raw = money.amountLeft ?? money.amount, let nano = Double(raw) else { return nil }
        return String(format: "%@ %.2f", currency, nano / 1e9)
    }
}
