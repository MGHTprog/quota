import Foundation

/// Contract for one AI quota data source.
///
/// Implementations own all provider-specific I/O (CLI, RPC, HTTP, auth files).
/// `QuotaService` and UI only talk to this protocol and `ProviderQuotaState`.
protocol QuotaProvider: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }
    var iconResourceName: String? { get }
    /// Monochrome mark for the popup filter tabs (template-tinted).
    var tabIconResourceName: String? { get }
    var fallbackGlyph: String { get }
    var accentColorHex: String { get }

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
    var iconResourceName: String? { nil }

    var tabIconResourceName: String? { nil }

    var fallbackGlyph: String {
        String(displayName.prefix(1)).uppercased()
    }

    var accentColorHex: String { "#3B82F6" }

    /// Default: providers are polled unless they override this.
    var isEnabled: Bool { true }

    /// Default: no connection to invalidate.
    func invalidateConnection() {}
}
