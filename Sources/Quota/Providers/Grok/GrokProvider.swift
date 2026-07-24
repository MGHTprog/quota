import Foundation

/// Grok provider: reads weekly Build credits via the CLI billing API.
///
/// Auth comes from `~/.grok/auth.json` (`grok login`).
final class GrokProvider: QuotaProvider {
    let id: ProviderID = .grok
    let displayName = "Grok"
    let iconResourceName: String? = "ProviderIconGrok"
    let fallbackGlyph = "xAI"
    let accentColorHex = "#111111"

    private let proxySettingsStore: ProxySettingsStore
    private var client: GrokBillingClient

    init(proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = GrokBillingClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        client.fetchBilling { [displayName] result in
            switch result {
            case .success(let response):
                let identity = ProviderIdentity(
                    displayName: displayName,
                    plan: response.displayPlan
                )
                // Mapping is non-throwing: usage defaults are applied at decode time.
                completion(.success(response.makeProviderState(identity: identity)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func stop() {}

    func invalidateConnection() {
        client = GrokBillingClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }
}
