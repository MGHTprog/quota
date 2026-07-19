import Foundation

// MARK: - Wire types (Grok CLI billing API)

/// Decoded payload of `GET .../v1/billing?format=credits`.
struct GrokBillingResponse: Decodable {
    var config: GrokBillingConfig
    /// Present on some response envelopes (CLI billing logs).
    var subscriptionTier: String?
}

struct GrokBillingConfig: Decodable {
    var creditUsagePercent: Double?
    var currentPeriod: GrokUsagePeriod?
    var billingPeriodEnd: Date?
    var productUsage: [GrokProductUsage]?
    var subscriptionTier: String?
}

struct GrokUsagePeriod: Decodable {
    var end: Date?
}

struct GrokProductUsage: Decodable {
    var product: String?
}

extension GrokBillingResponse {
    /// Subscription tier for the plan pill (e.g. "X Premium+").
    ///
    /// Do not fall back to `productUsage.product` — that is a product id like
    /// `GrokBuild`, not a user-facing plan name.
    var displayPlan: String? {
        let raw = subscriptionTier ?? config.subscriptionTier
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum GrokWindowID {
    static let weekly = "weekly"
}

// MARK: - Mapping -> ProviderQuotaState

extension GrokBillingResponse {
    func makeProviderState(
        identity: ProviderIdentity,
        now: Date = Date()
    ) throws -> ProviderQuotaState {
        guard let used = config.creditUsagePercent else {
            throw GrokQuotaError.missingUsageWindow
        }

        let usedPercent = used.clamped(to: 0...100)
        let window = QuotaWindow(
            id: GrokWindowID.weekly,
            title: L.weeklyTitle,
            usedPercent: usedPercent,
            remainingPercent: (100 - usedPercent).clamped(to: 0...100),
            resetsAt: config.currentPeriod?.end ?? config.billingPeriodEnd,
            isAvailable: true
        )

        return ProviderQuotaState(
            providerID: .grok,
            identity: identity,
            windows: [window],
            badges: [],
            updatedAt: now,
            sourceLabel: "cli-billing"
        )
    }
}

// MARK: - Errors

enum GrokQuotaError: LocalizedError {
    case notSignedIn
    case unauthorized
    case missingUsageWindow
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L.grokNotSignedIn
        case .unauthorized:
            return L.grokUnauthorized
        case .missingUsageWindow:
            return L.grokMissingUsageWindow
        case .invalidResponse:
            return L.invalidResponse
        case .requestFailed(let statusCode):
            return L.grokRequestFailed(statusCode)
        }
    }
}

// MARK: - Private helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
