import CFNetwork
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
            session: Self.makeSession(configuration: proxyConfiguration),
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

    static func makeSession(configuration: ProxyConfiguration) -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.default
        // Quota must always hit the network; never serve a stale billing snapshot.
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil

        switch configuration.mode {
        case .automatic:
            break
        case .manual:
            if let proxy = ProxyEndpoint(configuration.proxyURL) {
                sessionConfiguration.connectionProxyDictionary = proxy.connectionProxyDictionary
            }
        case .disabled:
            sessionConfiguration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false
            ]
        }

        return URLSession(configuration: sessionConfiguration)
    }
}

private struct ProxyEndpoint {
    var connectionProxyDictionary: [String: Any]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, let port = url.port else {
            return nil
        }

        switch url.scheme?.lowercased() {
        case "http", "https":
            connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port
            ]
        case "socks", "socks5":
            connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port
            ]
        default:
            return nil
        }
    }
}
