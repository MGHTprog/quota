import Foundation

/// Claude provider: reads Claude Code rate limits via the OAuth usage API.
///
/// Auth comes from the Claude Code CLI sign-in (macOS Keychain, or
/// `~/.claude/.credentials.json`). All Claude-specific I/O stays in
/// `Providers/Claude/`; Core and UI only see `QuotaProvider` /
/// `ProviderQuotaState`.
final class ClaudeProvider: QuotaProvider {
    let id: ProviderID = .claude
    let displayName = "Claude"
    let iconResourceName: String? = "ProviderIconClaude"
    let fallbackGlyph = "C"
    let accentColorHex = "#D97757"

    private let proxySettingsStore: ProxySettingsStore
    private var client: ClaudeUsageClient

    init(proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = ClaudeUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }

    /// Test seam: inject a preconfigured client.
    init(client: ClaudeUsageClient, proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = client
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        client.fetchUsage { [displayName] result in
            switch result {
            case .success(let fetchResult):
                let identity = ProviderIdentity(
                    displayName: displayName,
                    plan: fetchResult.plan
                )
                completion(.success(
                    fetchResult.response.makeProviderState(identity: identity)
                ))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func stop() {}

    func invalidateConnection() {
        // Rebuild the session so the next fetch picks up new proxy settings.
        client = ClaudeUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }
}
