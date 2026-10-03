import Foundation

/// Codex provider: reads rate limits via local `codex app-server` JSON-RPC.
///
/// All Codex-specific I/O stays in `Providers/Codex/`. Core and UI only see
/// `QuotaProvider` / `ProviderQuotaState`.
final class CodexProvider: QuotaProvider {
    let id: ProviderID = .codex
    /// Keep the provider's stable ID while showing its most recently used model.
    var displayName: String { modelNameReader.displayName(fallback: Self.configuredModelDisplayName()) }
    private let modelNameReader = CodexModelNameReader()
    let iconResourceName: String? = "ProviderIconCodex"
    let tabIconResourceName: String? = "TabIconCodex"
    let fallbackGlyph = "C"
    let accentColorHex = "#16A34A"

    private let client: CodexAppServerClient
    private var lastKnownPlan: String?

    private static func configuredModelDisplayName() -> String {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let config = try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8) else {
            return "GPT"
        }
        for line in config.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            let fields = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count == 2, fields[0] == "model",
                  let quote = fields[1].first, quote == "\"" || quote == "'",
                  let end = fields[1].dropFirst().firstIndex(of: quote) else { continue }
            let model = String(fields[1][fields[1].index(after: fields[1].startIndex)..<end])
            guard !model.isEmpty else { continue }
            if model.hasPrefix("gpt-") {
                let components = model.dropFirst(4).split(separator: "-")
                return "GPT-" + components.enumerated().map { index, part in
                    index == 0 ? String(part) : part.capitalized
                }.joined(separator: " ")
            }
            return model
        }
        return "GPT"
    }

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
