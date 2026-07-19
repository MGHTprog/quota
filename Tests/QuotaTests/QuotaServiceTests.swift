import Foundation
import Testing
@testable import Quota

private extension ProviderID {
    static let testProvider = ProviderID(rawValue: "test-provider")
}

@MainActor
@Test func primaryProviderUsesFirstEnabledInOrder() {
    let defaults = UserDefaults(suiteName: "QuotaServiceTests.selected")!
    defaults.removePersistentDomain(forName: "QuotaServiceTests.selected")
    let store = ProviderSettingsStore(defaults: defaults)
    store.configuration = ProviderSettingsConfiguration(
        providerOrder: [.testProvider, .codex],
        enabledProviderIDs: [.codex, .testProvider]
    )

    let service = QuotaService(
        registry: ProviderRegistry(providers: [
            FakeProvider(id: .codex, displayName: "Codex"),
            FakeProvider(id: .testProvider, displayName: "Test Provider"),
        ]),
        providerSettingsStore: store
    )

    #expect(service.primaryProviderID == ProviderID.testProvider)
}

@MainActor
@Test func primaryProviderFallsBackToFirstRegisteredProviderWithEmptySettings() {
    let defaults = UserDefaults(suiteName: "QuotaServiceTests.empty")!
    defaults.removePersistentDomain(forName: "QuotaServiceTests.empty")
    let store = ProviderSettingsStore(defaults: defaults)

    let service = QuotaService(
        registry: ProviderRegistry(providers: [
            FakeProvider(id: .testProvider, displayName: "Test Provider"),
            FakeProvider(id: .codex, displayName: "Codex"),
        ]),
        providerSettingsStore: store
    )

    #expect(service.primaryProviderID == ProviderID.testProvider)
}

@MainActor
@Test func primaryProviderSkipsDisabledProvidersInOrder() {
    let defaults = UserDefaults(suiteName: "QuotaServiceTests.fallback")!
    defaults.removePersistentDomain(forName: "QuotaServiceTests.fallback")
    let store = ProviderSettingsStore(defaults: defaults)
    store.configuration = ProviderSettingsConfiguration(
        providerOrder: [.testProvider, .codex],
        enabledProviderIDs: [.codex]
    )

    let service = QuotaService(
        registry: ProviderRegistry(providers: [
            FakeProvider(id: .codex, displayName: "Codex"),
            FakeProvider(id: .testProvider, displayName: "Test Provider"),
        ]),
        providerSettingsStore: store
    )

    #expect(service.primaryProviderID == ProviderID.codex)
}

@MainActor
@Test func orderedEnabledProvidersRespectUserOrder() {
    let configuration = ProviderSettingsConfiguration(
        providerOrder: [.grok, .codex],
        enabledProviderIDs: [.codex, .grok]
    )
    let registry = ProviderRegistry(providers: [
        FakeProvider(id: .codex, displayName: "Codex"),
        FakeProvider(id: .grok, displayName: "Grok"),
    ])

    let enabled = registry.enabledProviders(configuration: configuration).map(\.id)
    #expect(enabled == [ProviderID.grok, ProviderID.codex])
}

@Test func providerDisplayLimitIsFive() {
    #expect(ProviderDisplayLimits.maxEnabledCount == 5)
}

private final class FakeProvider: QuotaProvider {
    let id: ProviderID
    let displayName: String

    init(id: ProviderID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        completion(
            .success(
                ProviderQuotaState(
                    providerID: id,
                    identity: ProviderIdentity(displayName: displayName, plan: nil),
                    windows: [],
                    badges: [],
                    updatedAt: Date(),
                    sourceLabel: nil
                )
            )
        )
    }

    func stop() {}
}
