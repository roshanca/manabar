import Foundation

/// Devin quota via Connect RPC GetUserStatus.
///
/// Contract (adapted from burakgon/ai-usage-menubar / OpenUsage, MIT — see NOTICE):
/// - POST {server}/exa.seat_management_pb.SeatManagementService/GetUserStatus,
///   Connect-Protocol-Version: 1, apiKey in the JSON body (no Authorization header)
/// - response: userStatus.planStatus carries daily/weekly REMAINING percents
///   (converted here with 100 - x) and Unix reset timestamps;
///   planInfo.hideDailyQuota hides the daily window
///
/// Credential discovery order:
/// 1. ~/.local/share/devin/credentials.toml (windsurf_api_key, api_server_url)
/// 2. Devin's VS Code state DB (read-only sqlite3 query)
/// 3. API key entered in Settings (stored in ManaBar's own keychain item)
struct DevinProvider: UsageProvider {
    let id = ProviderID.devin

    private static let defaultServer = "https://server.codeium.com"
    private static let rpcPath = "/exa.seat_management_pb.SeatManagementService/GetUserStatus"

    private struct Response: Decodable {
        struct UserStatus: Decodable {
            struct PlanStatus: Decodable {
                let dailyQuotaRemainingPercent: Double?
                let weeklyQuotaRemainingPercent: Double?
                let dailyQuotaResetAtUnix: TimeInterval?
                let weeklyQuotaResetAtUnix: TimeInterval?
            }
            struct PlanInfo: Decodable {
                let hideDailyQuota: Bool?
                let planName: String?
            }
            let planStatus: PlanStatus?
            let planInfo: PlanInfo?
        }
        let userStatus: UserStatus?
    }

    struct Credentials: Sendable {
        let apiKey: String
        let serverURL: String
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        do {
            let credentials = try Self.discoverCredentials()
            guard let url = URL(string: credentials.serverURL + Self.rpcPath) else {
                throw ProviderFailure.transient("Invalid Devin server URL.")
            }
            var request = try URLRequest.jsonPOST(url, body: [
                "metadata": ["apiKey": credentials.apiKey],
            ])
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

            let (data, _) = try await HTTPClient.shared.send(request)
            let response = try JSONDecoder().decode(Response.self, from: data)

            guard let planStatus = response.userStatus?.planStatus else {
                throw ProviderFailure.transient("Devin quota data is unavailable.")
            }
            let hideDaily = response.userStatus?.planInfo?.hideDailyQuota == true

            var metrics: [QuotaMetric] = []
            if let remaining = planStatus.weeklyQuotaRemainingPercent {
                metrics.append(QuotaMetric(
                    id: "devin.weekly", kind: .weekly, title: "Weekly limit",
                    usedRatio: min(max((100 - remaining) / 100, 0), 1),
                    resetDate: DateParsing.parse(epochSeconds: planStatus.weeklyQuotaResetAtUnix)))
            }
            if let remaining = planStatus.dailyQuotaRemainingPercent {
                if hideDaily {
                    // Republish the daily value as the weekly window (reference behavior).
                    if metrics.isEmpty {
                        metrics.append(QuotaMetric(
                            id: "devin.weekly", kind: .weekly, title: "Weekly limit",
                            usedRatio: min(max((100 - remaining) / 100, 0), 1),
                            resetDate: DateParsing.parse(epochSeconds: planStatus.weeklyQuotaResetAtUnix)))
                    }
                } else {
                    metrics.insert(QuotaMetric(
                        id: "devin.daily", kind: .session, title: "Daily limit",
                        usedRatio: min(max((100 - remaining) / 100, 0), 1),
                        resetDate: DateParsing.parse(epochSeconds: planStatus.dailyQuotaResetAtUnix)), at: 0)
                }
            }
            guard !metrics.isEmpty else {
                throw ProviderFailure.transient("Devin quota data is unavailable.")
            }

            return ProviderSnapshot(
                providerID: id,
                planName: response.userStatus?.planInfo?.planName,
                metrics: metrics, extras: [], fetchedAt: Date())
        } catch {
            throw mapError(error, provider: id.displayName)
        }
    }

    // MARK: - Credential discovery

    static func discoverCredentials() throws -> Credentials {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let tomlURL = home.appending(path: ".local/share/devin/credentials.toml")
        if let toml = try? String(contentsOf: tomlURL, encoding: .utf8) {
            let values = Self.parseSimpleTOML(toml)
            if let key = values["windsurf_api_key"], !key.isEmpty {
                return Credentials(
                    apiKey: key,
                    serverURL: values["api_server_url"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultServer)
            }
        }

        let stateDB = home.appending(path: "Library/Application Support/Devin/User/globalStorage/state.vscdb")
        if FileManager.default.fileExists(atPath: stateDB.path()),
           let json = SecurityCLI.sqliteReadOnly(
               database: stateDB.path(),
               query: "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1"),
           let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = object["apiKey"] as? String, !key.isEmpty {
            return Credentials(apiKey: key, serverURL: defaultServer)
        }

        if let key = KeychainHelper.read(
            service: KeychainHelper.devinService, account: KeychainHelper.devinAccount),
           !key.isEmpty {
            return Credentials(apiKey: key, serverURL: defaultServer)
        }

        throw ProviderFailure.notConfigured("Devin API key not found — add one in Settings.")
    }

    /// Minimal flat `key = "value"` TOML scan — sufficient for credentials.toml.
    private static func parseSimpleTOML(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["),
                  let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
