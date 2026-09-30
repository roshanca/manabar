import Foundation

enum HTTPError: Error, Sendable {
    case badStatus(Int)
    case badResponse
}

/// Thin async/await wrapper over URLSession with bounded timeouts.
/// Never logs request or response bodies — they may carry credentials.
struct HTTPClient: Sendable {
    static let shared = HTTPClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    @discardableResult
    func send(_ request: URLRequest, acceptable: ClosedRange<Int> = 200...299) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.badResponse }
        guard acceptable.contains(http.statusCode) else { throw HTTPError.badStatus(http.statusCode) }
        return (data, http)
    }
}

extension URLRequest {
    static func jsonPOST(_ url: URL, body: [String: Any], headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func formPOST(_ url: URL, fields: [(String, String)], headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }
}
