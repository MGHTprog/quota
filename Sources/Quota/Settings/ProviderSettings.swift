import Foundation

/// How many providers the menu-bar popup can show comfortably as icon chips.
///
/// Panel width 260, side padding 12×2 → 236pt usable.
/// Chip 34 + gap 6, plus a fixed "All" chip:
///   providers 5 → 6 chips → 234pt (fits)
///   providers 6 → 7 chips → 274pt (overflow)
enum ProviderDisplayLimits {
    static let maxEnabledCount = 5
}

/// User-facing provider enablement and display order.
///
/// - `providerOrder`: left-to-right tab order (and priority).
/// - `enabledProviderIDs`: which providers appear in the popup / are refreshed.
/// - Primary (leftmost tab / Touch Bar when available) = first enabled in `providerOrder`.
struct ProviderSettingsConfiguration: Equatable {
    var providerOrder: [ProviderID]
    var enabledProviderIDs: Set<ProviderID>

    static let empty = ProviderSettingsConfiguration(
        providerOrder: [],
        enabledProviderIDs: []
    )

    /// Legacy empty settings mean “everything on, registry order”.
    var usesDefaultEnablement: Bool {
        providerOrder.isEmpty && enabledProviderIDs.isEmpty
    }

    func isEnabled(_ id: ProviderID) -> Bool {
        if usesDefaultEnablement { return true }
        return enabledProviderIDs.contains(id)
    }

    /// Full order of known providers (configured order, then any new ids appended).
    func resolvedOrder(availableIDs: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        var result: [ProviderID] = []
        for id in providerOrder where availableIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in availableIDs where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// Enabled providers in display order (popup tabs, refresh order).
    func orderedEnabledIDs(availableIDs: [ProviderID]) -> [ProviderID] {
        if usesDefaultEnablement {
            return availableIDs
        }
        return resolvedOrder(availableIDs: availableIDs).filter { enabledProviderIDs.contains($0) }
    }

    /// Primary provider = first enabled in order (leftmost tab; Touch Bar when available).
    func primaryProviderID(availableIDs: [ProviderID]) -> ProviderID? {
        orderedEnabledIDs(availableIDs: availableIDs).first
    }
}

/// Lightweight provider option shown in Settings and compact provider tabs.
struct ProviderSettingsOption: Equatable {
    var id: ProviderID
    var displayName: String
    var iconResourceName: String?
    var fallbackGlyph: String
    var accentColorHex: String

    init(
        id: ProviderID,
        displayName: String,
        iconResourceName: String? = nil,
        fallbackGlyph: String? = nil,
        accentColorHex: String = "#3B82F6"
    ) {
        self.id = id
        self.displayName = displayName
        self.iconResourceName = iconResourceName
        self.fallbackGlyph = fallbackGlyph ?? String(displayName.prefix(1)).uppercased()
        self.accentColorHex = accentColorHex
    }
}

/// Persists provider order and enablement in `UserDefaults`.
final class ProviderSettingsStore {
    static let shared = ProviderSettingsStore()

    private let defaults: UserDefaults
    private let orderKey = "provider.order"
    private let enabledProvidersKey = "provider.enabled"
    /// Legacy key from the old “展示” dropdown; migrated into order on read.
    private let legacySelectedProviderKey = "provider.selected"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: ProviderSettingsConfiguration {
        get {
            let order = (defaults.stringArray(forKey: orderKey) ?? [])
                .compactMap(ProviderID.init(rawValue:))
            var enabled = Set(
                (defaults.stringArray(forKey: enabledProvidersKey) ?? [])
                    .compactMap(ProviderID.init(rawValue:))
            )

            // Migrate pre-order settings: selected provider becomes highest priority.
            if order.isEmpty,
               let legacySelected = defaults.string(forKey: legacySelectedProviderKey)
                .map(ProviderID.init(rawValue:)) {
                var migratedOrder = [legacySelected]
                for id in enabled where id != legacySelected {
                    migratedOrder.append(id)
                }
                if enabled.isEmpty {
                    enabled = [legacySelected]
                } else {
                    enabled.insert(legacySelected)
                }
                return ProviderSettingsConfiguration(
                    providerOrder: migratedOrder,
                    enabledProviderIDs: enabled
                )
            }

            return ProviderSettingsConfiguration(
                providerOrder: order,
                enabledProviderIDs: enabled
            )
        }
        set {
            defaults.set(
                newValue.providerOrder.map(\.rawValue),
                forKey: orderKey
            )
            defaults.set(
                newValue.enabledProviderIDs.map(\.rawValue).sorted(),
                forKey: enabledProvidersKey
            )
            defaults.removeObject(forKey: legacySelectedProviderKey)
        }
    }
}
