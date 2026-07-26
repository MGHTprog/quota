import Foundation

/// Codex provider: reads rate limits via local `codex app-server` JSON-RPC.
///
/// All Codex-specific I/O stays in `Providers/Codex/`. Core and UI only see
/// `QuotaProvider` / `ProviderQuotaState`.
final class CodexProvider: QuotaProvider {
    let id: ProviderID = .codex
    /// User-facing brand name for this provider (owned here, not on `ProviderID`).
    let displayName = "Codex"
    let iconResourceName: String? = "ProviderIconCodex"
    let tabIconResourceName: String? = "TabIconCodex"
    let fallbackGlyph = "C"
    let accentColorHex = "#16A34A"

    private let client: CodexAppServerClient
    private var lastKnownPlan: String?

    init(
        proxySettingsStore: ProxySettingsStore = .shared,
        binaryLocator: CodexBinaryLocator = CodexBinaryLocator(),
        proxyEnvironmentBuilder: ProxyEnvironmentBuilder = ProxyEnvironmentBuilder(),
        managedProcessRegistry: ManagedProcessRegistry = ManagedProcessRegistry(),
        appMetadata: AppMetadata = .current
    ) {
        self.client = CodexAppServerClient(
            proxySettingsStore: proxySettingsStore,
            binaryLocator: binaryLocator,
            proxyEnvironmentBuilder: proxyEnvironmentBuilder,
            managedProcessRegistry: managedProcessRegistry,
            appMetadata: appMetadata
        )
    }

    /// Test seam: inject a preconfigured client.
    init(client: CodexAppServerClient) {
        self.client = client
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        // Account is best-effort (plan label). Rate limits are the source of truth.
        client.readAccount { [weak self] accountResult in
            guard let self else { return }

            if case .success(let account) = accountResult {
                self.lastKnownPlan = account.planType
            }

            self.client.readRateLimits { rateResult in
                switch rateResult {
                case .success(let response):
                    do {
                        let identity = ProviderIdentity(
                            displayName: self.displayName,
                            plan: self.lastKnownPlan
                        )
                        let state = try response.makeProviderState(identity: identity)
                        completion(.success(state))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        client.stop()
    }

    func invalidateConnection() {
        client.stop(notifyPending: false)
    }
}
