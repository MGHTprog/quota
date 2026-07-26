import Foundation

// MARK: - Wire types (Claude OAuth usage API)
//
// Endpoint: GET https://api.anthropic.com/api/oauth/usage
// (same source the Claude Code CLI uses for `/usage`).
//
// Field semantics (from live responses):
// - `limits`: authoritative list of rate-limit windows. Each entry carries
//   `group` (`session` / `weekly`), `percent` used (0...100), `resets_at`,
//   and an optional `scope.model.display_name` for per-model weekly pools.
// - `five_hour` / `seven_day`: legacy aggregate buckets with `utilization`
//   percent + `resets_at`. Only used when `limits` is absent or empty.

/// Decoded payload of `GET /api/oauth/usage`.
struct ClaudeUsageResponse: Decodable {
    var fiveHour: ClaudeUsageBucket? = nil
    var sevenDay: ClaudeUsageBucket? = nil
    var limits: [ClaudeUsageLimit]? = nil
}

struct ClaudeUsageBucket: Decodable {
    /// Percent of the window already used (0...100).
    var utilization: Double? = nil
    var resetsAt: Date? = nil
}

struct ClaudeUsageLimit: Decodable {
    struct Scope: Decodable {
        struct Model: Decodable {
            var displayName: String?
        }

        var model: Model?
    }

    /// Window family: `session` or `weekly`.
    var group: String? = nil
    /// Percent of the window already used (0...100).
    var percent: Double? = nil
    var resetsAt: Date? = nil
    var scope: Scope? = nil
}

enum ClaudeWindowID {
    static let session = "session"
    static let weekly = "weekly"

    /// Scoped weekly pools use `weekly@<scope>` so `QuotaWindow.localizedTitle`
    /// can re-render the scope after a language switch.
    static func weekly(scope: String) -> String {
        "\(weekly)@\(scope)"
    }
}

// MARK: - JSON decoding

enum ClaudeUsageCoding {
    /// Decoder for the OAuth usage API (snake_case keys, ISO-8601 dates).
    static func makeDecoder() -> JSONDecoder {
        QuotaJSONCoding.makeISO8601Decoder(convertFromSnakeCase: true)
    }
}

// MARK: - Mapping -> ProviderQuotaState

extension ClaudeUsageResponse {
    /// Maps a successfully decoded usage payload into UI state.
    ///
    /// Prefers the `limits` array (session first, then weekly pools in API
    /// order). Falls back to the legacy `five_hour` / `seven_day` buckets so
    /// older payload shapes still render.
    func makeProviderState(
        identity: ProviderIdentity,
        now: Date = Date()
    ) -> ProviderQuotaState {
        var windows = windowsFromLimits()
        if windows.isEmpty {
            windows = windowsFromLegacyBuckets()
        }

        return ProviderQuotaState(
            providerID: .claude,
            identity: identity,
            windows: windows,
            badges: [],
            updatedAt: now,
            sourceLabel: "oauth-usage"
        )
    }

    private func windowsFromLimits() -> [QuotaWindow] {
        guard let limits, !limits.isEmpty else { return [] }

        var sessionWindows: [QuotaWindow] = []
        var weeklyWindows: [QuotaWindow] = []
        var seenIDs = Set<String>()

        func appendWindow(
            _ limit: ClaudeUsageLimit,
            id: String,
            title: String,
            scope: String? = nil,
            to windows: inout [QuotaWindow]
        ) {
            guard seenIDs.insert(id).inserted else { return }
            let usedPercent = (limit.percent ?? 0).clamped(to: 0...100)
            windows.append(QuotaWindow(
                id: id,
                title: title,
                usedPercent: usedPercent,
                remainingPercent: (100 - usedPercent).clamped(to: 0...100),
                resetsAt: limit.resetsAt,
                isAvailable: true,
                scope: scope
            ))
        }

        for limit in limits {
            switch limit.group?.lowercased() {
            case "session":
                appendWindow(
                    limit,
                    id: ClaudeWindowID.session,
                    title: L.fiveHourTitle,
                    to: &sessionWindows
                )
            case "weekly":
                if let scope = limit.scopeDisplayName {
                    // Scoped id keeps notification thresholds per pool; the
                    // rendered title comes from QuotaWindow.localizedTitle.
                    appendWindow(
                        limit,
                        id: ClaudeWindowID.weekly(scope: scope),
                        title: L.weeklyTitle,
                        scope: scope,
                        to: &weeklyWindows
                    )
                } else {
                    appendWindow(
                        limit,
                        id: ClaudeWindowID.weekly,
                        title: L.weeklyTitle,
                        to: &weeklyWindows
                    )
                }
            default:
                continue
            }
        }

        return sessionWindows + weeklyWindows
    }

    private func windowsFromLegacyBuckets() -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let fiveHour {
            let used = (fiveHour.utilization ?? 0).clamped(to: 0...100)
            windows.append(QuotaWindow(
                id: ClaudeWindowID.session,
                title: L.fiveHourTitle,
                usedPercent: used,
                remainingPercent: (100 - used).clamped(to: 0...100),
                resetsAt: fiveHour.resetsAt,
                isAvailable: true
            ))
        }

        if let sevenDay {
            let used = (sevenDay.utilization ?? 0).clamped(to: 0...100)
            windows.append(QuotaWindow(
                id: ClaudeWindowID.weekly,
                title: L.weeklyTitle,
                usedPercent: used,
                remainingPercent: (100 - used).clamped(to: 0...100),
                resetsAt: sevenDay.resetsAt,
                isAvailable: true
            ))
        }

        return windows
    }
}

extension ClaudeUsageLimit {
    /// Model scope label for per-model weekly pools (e.g. "Fable").
    var scopeDisplayName: String? {
        let trimmed = scope?.model?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ClaudeCredentials {
    /// Subscription label for the plan pill (`max` → "Max").
    var displayPlan: String? {
        let trimmed = claudeAiOauth.subscriptionType?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.capitalized
    }
}

// MARK: - Errors

enum ClaudeQuotaError: LocalizedError {
    case notSignedIn
    case tokenExpired
    case unauthorized
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L.claudeNotSignedIn
        case .tokenExpired:
            return L.claudeTokenExpired
        case .unauthorized:
            return L.claudeUnauthorized
        case .invalidResponse:
            return L.invalidResponse
        case .requestFailed(let statusCode):
            return L.claudeRequestFailed(statusCode)
        }
    }
}
