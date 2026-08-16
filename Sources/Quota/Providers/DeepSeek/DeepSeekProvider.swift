import Foundation

/// DeepSeek provider: reads API balance via the balance endpoint.
///
/// Auth comes from environment variable `DEEPSEEK_API_KEY` or
/// `~/.deepseek/api_key` file.
final class DeepSeekProvider: QuotaProvider {
    let id: ProviderID = .deepseek
    let displayName = "DeepSeek"
    let iconResourceName: String? = "ProviderIconDeepSeek"
    let tabIconResourceName: String? = "TabIconDeepSeek"
    let fallbackGlyph = "DS"
    let accentColorHex = "#4F46E5" // Indigo

    private let proxySettingsStore: ProxySettingsStore
    private var client: DeepSeekUsageClient

    init(proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = DeepSeekUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }

    /// Test seam: inject a preconfigured client.
    init(client: DeepSeekUsageClient, proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = client
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        client.fetchBalance { [displayName] result in
            switch result {
            case .success(let response):
                let identity = ProviderIdentity(
                    displayName: displayName,
                    plan: nil // DeepSeek doesn't expose plan info
                )
                completion(.success(
                    response.makeProviderState(identity: identity)
                ))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func stop() {}

    func invalidateConnection() {
        // Rebuild the session so the next fetch picks up new proxy settings.
        client = DeepSeekUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }
}
