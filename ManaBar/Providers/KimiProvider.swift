import Foundation

/// Kimi Coding Plan usage: GET {api host}/coding/v1/usages with a Bearer token.
/// Response fields verified against the live service (see plan): usages.limit_5h /
/// limit_7d carry used_ratio + reset_time; booster_wallet carries the booster
/// balance and this month's booster spend.
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
            let unit: String?
            let currency: String?
            let priceInCents: Double?

            enum CodingKeys: String, CodingKey { case amount, unit, currency, priceInCents }

            // priceInCents arrives as a string.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                amount = try? container.decode(String.self, forKey: .amount)
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
                usedRatio: ratio, resetDate: window.resetTime.flatMap(DateParsing.parse)))
        }
        if let window = response.usages?.limit7d, let ratio = window.usedRatio {
            metrics.append(QuotaMetric(
                id: "kimi.7d", kind: .weekly, title: "Weekly limit",
                usedRatio: ratio, resetDate: window.resetTime.flatMap(DateParsing.parse)))
        }
        guard !metrics.isEmpty else {
            throw ProviderFailure.transient("Kimi usage response had no quota windows.")
        }

        var extras: [ExtraInfo] = []
        if let balance = response.boosterWallet?.balance, let formatted = Self.formatMoney(balance) {
            extras.append(ExtraInfo(id: "kimi.booster", label: "Booster balance", value: formatted))
        }
        if let monthly = response.boosterWallet?.monthlyUsed, let formatted = Self.formatMoney(monthly) {
            extras.append(ExtraInfo(id: "kimi.monthly", label: "Booster this month", value: formatted))
        }

        return ProviderSnapshot(
            providerID: id, planName: nil,
            metrics: metrics, extras: extras, fetchedAt: Date())
    }

    /// balance.amount arrives in nano-units (e.g. "7500000000" ≈ ¥7.50);
    /// monthlyUsed carries priceInCents instead.
    private static func formatMoney(_ money: Response.Money) -> String? {
        let currency = money.currency ?? "CNY"
        if let cents = money.priceInCents {
            return String(format: "%@ %.2f", currency, cents / 100)
        }
        guard let raw = money.amount, let nano = Double(raw) else { return nil }
        return String(format: "%@ %.2f", currency, nano / 1e9)
    }
}
