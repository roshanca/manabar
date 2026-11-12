import Foundation

/// DeepSeek wallet balance via the platform API.
///
/// GET https://api.deepseek.com/user/balance with
/// `Authorization: Bearer <api key>` returns `is_available` plus one
/// `balance_infos` entry per currency; amounts arrive as decimal strings
/// ("36.64"). There is no quota window — the popover shows the wallet
/// block and nothing appears in the menu bar.
struct DeepSeekProvider: UsageProvider {
    let id = ProviderID.deepseek

    private struct Response: Decodable {
        struct BalanceInfo: Decodable {
            let currency: String?
            let totalBalance: String?
            let grantedBalance: String?
            let toppedUpBalance: String?

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance = "total_balance"
                case grantedBalance = "granted_balance"
                case toppedUpBalance = "topped_up_balance"
            }
        }
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        do {
            let store = DeepSeekCredentialStore.shared
            let (key, generation) = try await store.apiKey()
            guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
                throw ProviderFailure.transient("Invalid DeepSeek API URL.")
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, _) = try await HTTPClient.shared.send(request)
            let response = try JSONDecoder().decode(Response.self, from: data)

            let balances = (response.balanceInfos ?? []).compactMap { info -> WalletBalance? in
                guard let currency = info.currency, !currency.isEmpty,
                      let totalRaw = info.totalBalance,
                      let total = Decimal(string: totalRaw) else { return nil }
                return WalletBalance(
                    currency: currency,
                    total: total,
                    granted: info.grantedBalance.flatMap { Decimal(string: $0) } ?? 0,
                    toppedUp: info.toppedUpBalance.flatMap { Decimal(string: $0) } ?? 0)
            }
            guard !balances.isEmpty else {
                throw ProviderFailure.transient("DeepSeek balance response had no balances.")
            }

            var snapshot = ProviderSnapshot(
                providerID: id, planName: nil,
                metrics: [], extras: [], fetchedAt: Date())
            snapshot.balances = await store.trackSpend(balances, generation: generation)
            snapshot.isAvailable = response.isAvailable
            return snapshot
        } catch HTTPError.badStatus(let code) where code == 401 || code == 403 {
            throw ProviderFailure.authExpired("DeepSeek API key rejected — update it in Settings.")
        } catch {
            throw mapError(error, provider: id.displayName)
        }
    }
}
