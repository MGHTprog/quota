import Foundation

// MARK: - Quota window

/// One usage window shown in the UI (session, weekly, credits, …).
///
/// `id` is stable within a provider so notifications can track thresholds per window.
/// `title` should already be localized by the provider when mapping.
struct QuotaWindow: Equatable, Sendable {
    var id: String
    var title: String
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var isAvailable: Bool

    var resetText: String {
        guard isAvailable, let resetsAt else {
            return "\(L.reset) --"
        }

        Self.resetFormatter.locale = L.locale
        return "\(L.reset) " + Self.resetFormatter.string(from: resetsAt)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    static func unavailable(id: String, title: String) -> QuotaWindow {
        QuotaWindow(
            id: id,
            title: title,
            usedPercent: 0,
            remainingPercent: 0,
            resetsAt: nil,
            isAvailable: false
        )
    }

    /// Neutral empty row before real data arrives (no provider-specific labels).
    static var empty: QuotaWindow {
        unavailable(id: "", title: "--")
    }
}

// MARK: - Identity

/// Account-facing labels for a provider card / header.
struct ProviderIdentity: Equatable, Sendable {
    var displayName: String
    var plan: String?
}

// MARK: - Provider badges

/// Small provider-supplied labels shown next to the provider heading.
///
/// Providers should map source-specific extras (credits, plan hints, account
/// state) into badges instead of adding provider-specific fields here.
struct ProviderBadge: Equatable, Sendable {
    var text: String
}

// MARK: - Snapshot

/// Provider-agnostic quota snapshot.
///
/// Every `QuotaProvider` maps its raw response into this type.
/// UI layers (menu bar, Touch Bar, notifications) should only consume this model.
struct ProviderQuotaState: Equatable, Sendable {
    var providerID: ProviderID
    var identity: ProviderIdentity
    /// Ordered by display priority. May be empty when no windows are available.
    var windows: [QuotaWindow]
    /// Optional provider-supplied summary labels for the header.
    var badges: [ProviderBadge]
    var updatedAt: Date
    /// Optional fetch-path label for diagnostics (e.g. `"app-server"`).
    var sourceLabel: String?

    /// First `rowCount` windows for the fixed two-row menu / Touch Bar layout.
    /// Missing slots are filled with `QuotaWindow.empty` (not provider-specific labels).
    func windowsForCompactDisplay(rowCount: Int = 2) -> [QuotaWindow] {
        precondition(rowCount > 0)
        var rows = Array(windows.prefix(rowCount))
        if rows.count < rowCount {
            rows.append(contentsOf: repeatElement(.empty, count: rowCount - rows.count))
        }
        return rows
    }
}
