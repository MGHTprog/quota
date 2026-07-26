import Foundation

/// HTTP client for Grok CLI billing (`cli-chat-proxy.grok.com`).
final class GrokBillingClient {
    private let endpoint: URL
    private let session: URLSession
    private let authStore: GrokAuthStore
    private let decoder: JSONDecoder

    init(
        endpoint: URL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
        session: URLSession,
        authStore: GrokAuthStore = GrokAuthStore()
    ) {
        self.endpoint = endpoint
        self.session = session
        self.authStore = authStore
        self.decoder = GrokBillingCoding.makeDecoder()
    }

    convenience init(
        proxyConfiguration: ProxyConfiguration,
        authStore: GrokAuthStore = GrokAuthStore()
    ) {
        self.init(
            session: ProxiedURLSession.make(configuration: proxyConfiguration),
            authStore: authStore
        )
    }

    func fetchBilling(completion: @escaping (Result<GrokBillingResponse, Error>) -> Void) {
        let accessToken: String
        do {
            accessToken = try authStore.loadAccessToken()
        } catch {
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Quota/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(GrokQuotaError.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200..<300:
                guard let data else {
                    completion(.failure(GrokQuotaError.invalidResponse))
                    return
                }
                do {
                    completion(.success(try decoder.decode(GrokBillingResponse.self, from: data)))
                } catch {
                    completion(.failure(GrokQuotaError.invalidResponse))
                }
            case 401, 403:
                completion(.failure(GrokQuotaError.unauthorized))
            default:
                completion(.failure(GrokQuotaError.requestFailed(httpResponse.statusCode)))
            }
        }.resume()
    }

}
