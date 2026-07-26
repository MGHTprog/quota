import Foundation

/// HTTP client for the Claude OAuth usage API (`api.anthropic.com/api/oauth/usage`).
final class ClaudeUsageClient {
    /// Result carries the plan label from local credentials alongside the payload.
    struct FetchResult {
        var response: ClaudeUsageResponse
        var plan: String?
    }

    private let endpoint: URL
    private let session: URLSession
    private let authStore: ClaudeAuthStore
    private let decoder: JSONDecoder

    init(
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        session: URLSession,
        authStore: ClaudeAuthStore = ClaudeAuthStore()
    ) {
        self.endpoint = endpoint
        self.session = session
        self.authStore = authStore
        self.decoder = ClaudeUsageCoding.makeDecoder()
    }

    convenience init(
        proxyConfiguration: ProxyConfiguration,
        authStore: ClaudeAuthStore = ClaudeAuthStore()
    ) {
        self.init(
            session: ProxiedURLSession.make(configuration: proxyConfiguration),
            authStore: authStore
        )
    }

    func fetchUsage(completion: @escaping (Result<FetchResult, Error>) -> Void) {
        // Off the main thread: the first Keychain read can block on the system
        // permission prompt, and must not freeze the UI while it waits.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadCredentialsAndRequest(completion: completion)
        }
    }

    private func loadCredentialsAndRequest(
        completion: @escaping (Result<FetchResult, Error>) -> Void
    ) {
        let credentials: ClaudeCredentials
        do {
            credentials = try authStore.loadCredentials()
        } catch {
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Quota/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "Bearer \(credentials.claudeAiOauth.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        // OAuth tokens are only accepted with this beta header.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let plan = credentials.displayPlan
        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ClaudeQuotaError.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200..<300:
                guard let data else {
                    completion(.failure(ClaudeQuotaError.invalidResponse))
                    return
                }
                do {
                    let payload = try decoder.decode(ClaudeUsageResponse.self, from: data)
                    completion(.success(FetchResult(response: payload, plan: plan)))
                } catch {
                    completion(.failure(ClaudeQuotaError.invalidResponse))
                }
            case 401, 403:
                completion(.failure(ClaudeQuotaError.unauthorized))
            default:
                completion(.failure(ClaudeQuotaError.requestFailed(httpResponse.statusCode)))
            }
        }.resume()
    }
}
