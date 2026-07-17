import Foundation

/// Contract for one AI quota data source.
///
/// Implementations own all provider-specific I/O (CLI, RPC, HTTP, auth files).
/// `QuotaService` and UI only talk to this protocol and `ProviderQuotaState`.
protocol QuotaProvider: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }

    /// When `false`, `QuotaService` skips this provider during refresh.
    var isEnabled: Bool { get }

    /// Fetch a fresh snapshot.
    ///
    /// Call the completion exactly once. `QuotaService` applies its own refresh
    /// timeout and may ignore late callbacks after a newer generation starts.
    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void)

    /// Tear down child processes / network. Called on app quit.
    func stop()

    /// Drop live connections so the next `fetch` reconnects
    /// (for example after proxy settings change).
    func invalidateConnection()
}

extension QuotaProvider {
    /// Default: providers are polled unless they override this.
    var isEnabled: Bool { true }

    /// Default: no connection to invalidate.
    func invalidateConnection() {}
}
