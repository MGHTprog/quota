import CFNetwork
import Foundation

/// Builds `URLSession`s that honor the app's proxy settings.
///
/// Shared by HTTP-based providers (Grok billing, Claude usage). Caching is
/// always disabled — quota data must never be served stale.
enum ProxiedURLSession {
    static func make(configuration: ProxyConfiguration) -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.default
        // Quota must always hit the network; never serve a stale snapshot.
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
