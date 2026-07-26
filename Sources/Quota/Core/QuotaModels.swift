import Foundation

// MARK: - Quota window

/// One usage window shown in the UI (session, weekly, credits, …).
///
/// `id` is stable within a provider so notifications can track thresholds per window.
/// Prefer `localizedTitle` in UI — do not rely on `title` remaining current after a language switch.
struct QuotaWindow: Equatable, Sendable {
    var id: String
    /// Fallback / seed title from the provider (may be stale if language changed).
    var title: String
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var isAvailable: Bool

    /// Title resolved for the current UI language from `id` when possible.
    ///
    /// Ids may carry a scope suffix after `@` (e.g. `weekly@Fable`) so scoped
    /// windows stay distinguishable after a language switch.
    var localizedTitle: String {
        let normalized = id.lowercased()
        if normalized.contains("week") {
            if let scope = scopeName {
                return "\(L.weeklyTitle) · \(scope)"
            }
            return L.weeklyTitle
        }
        if normalized.contains("five")
            || normalized.contains("hour")
            || normalized.contains("session") {
            return L.fiveHourTitle
        }
        return title
    }

    /// Scope suffix encoded in the id (`weekly@Fable` → `Fable`).
    private var scopeName: String? {
        guard let range = id.range(of: "@") else { return nil }
        let name = String(id[range.upperBound...])
        return name.isEmpty ? nil : name
    }

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
/// Prefer structured kinds so the UI can localize at draw time (language switch
/// without waiting for the next fetch).
struct ProviderBadge: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text(String)
        case resetCredits(Int)
    }

    var kind: Kind

    static func text(_ value: String) -> ProviderBadge {
        ProviderBadge(kind: .text(value))
    }

    static func resetCredits(_ count: Int) -> ProviderBadge {
        ProviderBadge(kind: .resetCredits(count))
    }

    /// Localized label for the current UI language.
    var localizedText: String {
        switch kind {
        case .text(let value):
            return value
        case .resetCredits(let count):
            return L.resetCreditsSuffix(count)
        }
    }
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

    /// First `rowCount` windows for fixed multi-slot UIs (e.g. Touch Bar).
    /// Missing slots are filled with `QuotaWindow.empty`.
    /// Menu bar should prefer `windows` directly so providers without a slot
    /// (Grok weekly-only) do not show a fake empty row.
    func windowsForCompactDisplay(rowCount: Int = 2) -> [QuotaWindow] {
        precondition(rowCount > 0)
        var rows = Array(windows.prefix(rowCount))
        if rows.count < rowCount {
            rows.append(contentsOf: repeatElement(.empty, count: rowCount - rows.count))
        }
        return rows
    }
}

// MARK: - Shared helpers

extension Comparable {
    /// Clamps to `range` (used by providers to keep percents in 0...100).
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
