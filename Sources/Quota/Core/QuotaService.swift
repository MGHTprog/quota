import Foundation

/// Receives per-provider quota updates and failures from `QuotaService`.
@MainActor
protocol QuotaServiceObserver: AnyObject {
    func quotaService(_ service: QuotaService, didUpdate state: ProviderQuotaState)
    func quotaService(
        _ service: QuotaService,
        didFail error: Error,
        providerID: ProviderID,
        lastState: ProviderQuotaState?
    )
}

/// Polls every enabled `QuotaProvider` and fans results out to observers.
///
/// Provider-agnostic: registering another provider in `ProviderRegistry` is enough
/// for it to refresh. UI decides which provider(s) to render.
@MainActor
final class QuotaService {
    private enum Defaults {
        /// Default poll interval (2 minutes).
        static let refreshInterval: TimeInterval = 120
        /// How long a single provider fetch may stay in-flight before the lock is released.
        static let refreshTimeout: TimeInterval = 30
    }

    private let registry: ProviderRegistry
    private let providerSettingsStore: ProviderSettingsStore
    private let refreshInterval: TimeInterval
    private let refreshTimeout: TimeInterval
    private let mainQueue = DispatchQueue.main

    private var refreshTimer: DispatchSourceTimer?
    private var refreshTimeoutTimers: [ProviderID: DispatchSourceTimer] = [:]
    private var observers = NSHashTable<AnyObject>.weakObjects()
    private var inFlightProviderIDs: Set<ProviderID> = []
    /// Bumped per provider so stale callbacks are ignored after reconnect / newer refresh.
    private var refreshGenerations: [ProviderID: Int] = [:]

    private(set) var states: [ProviderID: ProviderQuotaState] = [:]

    /// Provider shown in the single-slot menu bar / Touch Bar.
    ///
    /// Uses the user's selected provider when it is registered and enabled;
    /// otherwise falls back to the first enabled registered provider.
    var primaryProvider: (any QuotaProvider)? {
        registry.primaryProvider(configuration: providerSettingsStore.configuration)
    }

    var primaryProviderID: ProviderID? {
        primaryProvider?.id
    }

    /// Display name from the registered provider instance (never hardcode brands in UI).
    func displayName(for providerID: ProviderID) -> String {
        registry.provider(id: providerID)?.displayName ?? providerID.rawValue
    }

    init(
        registry: ProviderRegistry,
        providerSettingsStore: ProviderSettingsStore = .shared,
        refreshInterval: TimeInterval = Defaults.refreshInterval,
        refreshTimeout: TimeInterval = Defaults.refreshTimeout
    ) {
        self.registry = registry
        self.providerSettingsStore = providerSettingsStore
        self.refreshInterval = refreshInterval
        self.refreshTimeout = refreshTimeout
    }

    var providerSettingsOptions: [ProviderSettingsOption] {
        registry.settingsOptions
    }

    var visibleProviderOptions: [ProviderSettingsOption] {
        registry
            .enabledProviders(configuration: providerSettingsStore.configuration)
            .map { ProviderSettingsOption(id: $0.id, displayName: $0.displayName) }
    }

    var visibleStates: [ProviderQuotaState] {
        let ids = visibleProviderOptions.map(\.id)
        return ids.compactMap { states[$0] }
    }

    func addObserver(_ observer: QuotaServiceObserver) {
        observers.add(observer)
        for state in states.values {
            observer.quotaService(self, didUpdate: state)
        }
    }

    func start() {
        guard refreshTimer == nil else { return }

        debugLog("[Quota] refresh loop started (interval=\(Int(refreshInterval))s)")
        refreshAll()

        let timer = DispatchSource.makeTimerSource(queue: mainQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshAll()
        }
        timer.resume()
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        cancelAllTimeouts()
        inFlightProviderIDs.removeAll()
        registry.stopAll()
    }

    /// Invalidate provider connections and force a full refresh (e.g. proxy change).
    func reconnectAndRefresh() {
        for id in inFlightProviderIDs {
            _ = bumpGeneration(for: id)
        }
        inFlightProviderIDs.removeAll()
        cancelAllTimeouts()
        registry.invalidateAllConnections()
        refreshAll()
    }

    func refreshAll() {
        for provider in registry.enabledProviders(configuration: providerSettingsStore.configuration) {
            refresh(provider: provider)
        }
    }

    func refresh(providerID: ProviderID) {
        let configuration = providerSettingsStore.configuration
        guard configuration.isEnabled(providerID),
              let provider = registry.provider(id: providerID),
              provider.isEnabled else {
            return
        }
        refresh(provider: provider)
    }

    // MARK: - Private

    private func refresh(provider: any QuotaProvider) {
        let id = provider.id
        guard !inFlightProviderIDs.contains(id) else { return }

        inFlightProviderIDs.insert(id)
        let generation = bumpGeneration(for: id)
        startRefreshTimeout(for: id, generation: generation)
        debugLog("[Quota] refreshing \(id.rawValue)")

        provider.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.refreshGenerations[id] == generation else { return }

                self.cancelRefreshTimeout(for: id)
                self.inFlightProviderIDs.remove(id)

                switch result {
                case .success(let state):
                    self.states[id] = state
                    debugLog("[Quota] \(id.rawValue) updated")
                    self.notifyUpdate(state)
                case .failure(let error):
                    debugLog("[Quota] \(id.rawValue) failed: \(error.localizedDescription)")
                    self.notifyFailure(error, providerID: id)
                }
            }
        }
    }

    private func bumpGeneration(for id: ProviderID) -> Int {
        let next = (refreshGenerations[id] ?? 0) &+ 1
        refreshGenerations[id] = next
        return next
    }

    /// Releases the in-flight lock after `refreshTimeout`.
    ///
    /// Does not mark the refresh as failed and does not clear cached state.
    /// A late success for the same generation is still accepted; a newer refresh
    /// bumps the generation and ignores the late callback.
    private func startRefreshTimeout(for id: ProviderID, generation: Int) {
        cancelRefreshTimeout(for: id)
        let timer = DispatchSource.makeTimerSource(queue: mainQueue)
        timer.schedule(deadline: .now() + refreshTimeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.refreshGenerations[id] == generation else { return }
            guard self.inFlightProviderIDs.contains(id) else { return }

            debugLog("[Quota] \(id.rawValue) refresh timed out after \(Int(self.refreshTimeout))s")
            self.inFlightProviderIDs.remove(id)
            self.refreshTimeoutTimers[id] = nil
        }
        timer.resume()
        refreshTimeoutTimers[id] = timer
    }

    private func cancelRefreshTimeout(for id: ProviderID) {
        refreshTimeoutTimers[id]?.cancel()
        refreshTimeoutTimers[id] = nil
    }

    private func cancelAllTimeouts() {
        for timer in refreshTimeoutTimers.values {
            timer.cancel()
        }
        refreshTimeoutTimers.removeAll()
    }

    private func notifyUpdate(_ state: ProviderQuotaState) {
        for observer in observers.allObjects {
            (observer as? QuotaServiceObserver)?.quotaService(self, didUpdate: state)
        }
    }

    private func notifyFailure(_ error: Error, providerID: ProviderID) {
        let last = states[providerID]
        for observer in observers.allObjects {
            (observer as? QuotaServiceObserver)?.quotaService(
                self,
                didFail: error,
                providerID: providerID,
                lastState: last
            )
        }
    }
}
