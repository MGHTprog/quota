import Foundation

// MARK: - Wire types (Codex app-server JSON-RPC)

/// Decoded payload of `account/rateLimits/read`.
struct GetAccountRateLimitsResponse: Decodable {
    var rateLimits: RateLimitSnapshot
    var rateLimitResetCredits: RateLimitResetCredits?
}

/// Decoded payload of `account/read`.
struct AccountResponse: Decodable {
    var account: AccountInfo
}

/// Subset of Codex account fields used by the UI (plan label).
struct AccountInfo: Decodable {
    var planType: String?
}

/// Primary/secondary windows as returned by app-server.
struct RateLimitSnapshot: Decodable {
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
}

/// One rate-limit window from app-server (percent used + optional reset time).
struct RateLimitWindow: Decodable {
    var usedPercent: Double
    var windowDurationMins: Int?
    var resetsAt: TimeInterval?
}

/// Optional reset-credit balance when the account exposes it.
struct RateLimitResetCredits: Decodable, Equatable {
    var availableCount: Int?
}

// MARK: - Window ids (Codex-private)

/// Stable window ids used only when mapping Codex responses.
///
/// Keep these private to the Codex provider package. UI and notifications must
/// not switch on these values — they should use `QuotaWindow.title` / `id` generically.
enum CodexWindowID {
    static let fiveHour = "fiveHour"
    static let weekly = "weekly"
}

// MARK: - Mapping → ProviderQuotaState

extension GetAccountRateLimitsResponse {
    func makeProviderState(
        identity: ProviderIdentity,
        now: Date = Date()
    ) throws -> ProviderQuotaState {
        guard rateLimits.primary != nil || rateLimits.secondary != nil else {
            throw CodexQuotaError.missingRateLimitWindow
        }

        var fiveHour: RateLimitWindow?
        var weekly: RateLimitWindow?

        classify(rateLimits.primary, fallback: .fiveHour, fiveHour: &fiveHour, weekly: &weekly)
        classify(rateLimits.secondary, fallback: .weekly, fiveHour: &fiveHour, weekly: &weekly)

        // Always emit both slots so a temporarily missing 5h limit still occupies a row as "--".
        let windows: [QuotaWindow] = [
            Self.quotaWindow(from: fiveHour, id: CodexWindowID.fiveHour, title: L.fiveHourTitle),
            Self.quotaWindow(from: weekly, id: CodexWindowID.weekly, title: L.weeklyTitle)
        ]

        return ProviderQuotaState(
            providerID: .codex,
            identity: identity,
            windows: windows,
            badges: Self.badges(from: rateLimitResetCredits),
            updatedAt: now,
            sourceLabel: "app-server"
        )
    }

    private static func badges(from resetCredits: RateLimitResetCredits?) -> [ProviderBadge] {
        guard let availableCount = resetCredits?.availableCount else {
            return []
        }
        return [.resetCredits(availableCount)]
    }

    /// Classifies a wire window as session (5h) vs weekly for mapping.
    private enum WindowKind {
        case fiveHour
        case weekly
    }

    private static func quotaWindow(from window: RateLimitWindow?, id: String, title: String) -> QuotaWindow {
        window?.asQuotaWindow(id: id, title: title) ?? .unavailable(id: id, title: title)
    }

    private func classify(
        _ window: RateLimitWindow?,
        fallback: WindowKind,
        fiveHour: inout RateLimitWindow?,
        weekly: inout RateLimitWindow?
    ) {
        guard let window else { return }

        let kind: WindowKind
        if let durationMinutes = window.windowDurationMins {
            // Windows longer than one day are treated as the weekly bucket.
            let minutesPerDay = 24 * 60
            kind = durationMinutes > minutesPerDay ? .weekly : .fiveHour
        } else {
            // Legacy primary/secondary meaning when duration is absent.
            kind = fallback
        }

        switch kind {
        case .fiveHour:
            if fiveHour == nil { fiveHour = window }
        case .weekly:
            if weekly == nil { weekly = window }
        }
    }
}

// MARK: - Errors

/// Codex-local failures surfaced through `QuotaProvider.fetch`.
enum CodexQuotaError: LocalizedError {
    case codexBinaryMissing
    case missingRateLimitWindow
    case invalidResponse
    case requestTimedOut
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .codexBinaryMissing:
            return L.codexBinaryMissing
        case .missingRateLimitWindow:
            return L.missingRateLimitWindow
        case .invalidResponse:
            return L.invalidResponse
        case .requestTimedOut:
            return L.requestTimedOut
        case .rpcError(let message):
            return message
        }
    }
}

// MARK: - Private helpers

private extension RateLimitWindow {
    func asQuotaWindow(id: String, title: String) -> QuotaWindow {
        let used = usedPercent.clamped(to: 0...100)
        return QuotaWindow(
            id: id,
            title: title,
            usedPercent: used,
            remainingPercent: (100 - used).clamped(to: 0...100),
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
            isAvailable: true
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
