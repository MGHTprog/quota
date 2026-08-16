import Foundation

/// HTTP client for the DeepSeek balance API (`api.deepseek.com/user/balance`).
final class DeepSeekUsageClient {
    private let endpoint: URL
    private let session: URLSession
    private let authStore: DeepSeekAuthStore
    private let decoder: JSONDecoder

    init(
        endpoint: URL = URL(string: "https://api.deepseek.com/user/balance")!,
        session: URLSession,
        authStore: DeepSeekAuthStore = DeepSeekAuthStore()
    ) {
        self.endpoint = endpoint
        self.session = session
        self.authStore = authStore
        self.decoder = DeepSeekBalanceCoding.makeDecoder()
    }

    convenience init(
        proxyConfiguration: ProxyConfiguration,
        authStore: DeepSeekAuthStore = DeepSeekAuthStore()
    ) {
        self.init(
            session: ProxiedURLSession.make(configuration: proxyConfiguration),
            authStore: authStore
        )
    }

    func fetchBalance(completion: @escaping (Result<DeepSeekBalanceResponse, Error>) -> Void) {
        // Off the main thread: API key file read can block on disk I/O.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadAPIKeyAndRequest(completion: completion)
        }
    }

    private func loadAPIKeyAndRequest(
        completion: @escaping (Result<DeepSeekBalanceResponse, Error>) -> Void
    ) {
        let apiKey: String
        do {
            apiKey = try authStore.loadAPIKey()
        } catch {
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Quota/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DeepSeekQuotaError.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200..<300:
                guard let data else {
                    completion(.failure(DeepSeekQuotaError.invalidResponse))
                    return
                }
                do {
                    let payload = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
                    completion(.success(payload))
                } catch {
                    completion(.failure(DeepSeekQuotaError.invalidResponse))
                }
            case 401, 403:
                completion(.failure(DeepSeekQuotaError.unauthorized))
            default:
                completion(.failure(DeepSeekQuotaError.requestFailed(httpResponse.statusCode)))
            }
        }.resume()
    }
}
