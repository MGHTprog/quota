import Foundation

/// User-facing provider enablement and primary-display selection.
struct ProviderSettingsConfiguration: Equatable {
    var selectedProviderID: ProviderID?
    var enabledProviderIDs: Set<ProviderID>

    static let empty = ProviderSettingsConfiguration(
        selectedProviderID: nil,
        enabledProviderIDs: []
    )

    func isEnabled(_ id: ProviderID) -> Bool {
        enabledProviderIDs.isEmpty || enabledProviderIDs.contains(id)
    }
}

/// Lightweight provider option shown in Settings.
struct ProviderSettingsOption: Equatable {
    var id: ProviderID
    var displayName: String
}

/// Persists provider display and enablement choices in `UserDefaults`.
final class ProviderSettingsStore {
    static let shared = ProviderSettingsStore()

    private let defaults: UserDefaults
    private let selectedProviderKey = "provider.selected"
    private let enabledProvidersKey = "provider.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: ProviderSettingsConfiguration {
        get {
            let selectedID = defaults.string(forKey: selectedProviderKey).map(ProviderID.init(rawValue:))
            let enabledIDs = Set(
                (defaults.stringArray(forKey: enabledProvidersKey) ?? [])
                    .compactMap(ProviderID.init(rawValue:))
            )
            return ProviderSettingsConfiguration(
                selectedProviderID: selectedID,
                enabledProviderIDs: enabledIDs
            )
        }
        set {
            if let selectedProviderID = newValue.selectedProviderID {
                defaults.set(selectedProviderID.rawValue, forKey: selectedProviderKey)
            } else {
                defaults.removeObject(forKey: selectedProviderKey)
            }
            defaults.set(
                newValue.enabledProviderIDs.map(\.rawValue).sorted(),
                forKey: enabledProvidersKey
            )
        }
    }
}
