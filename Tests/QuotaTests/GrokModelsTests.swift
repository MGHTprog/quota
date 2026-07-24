import Foundation
import Testing
@testable import Quota

@Test func mapsGrokBillingToWeeklyWindow() {
    let reset = Date(timeIntervalSince1970: 1_900_000_000)
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 25,
            currentPeriod: GrokUsagePeriod(
                type: "USAGE_PERIOD_TYPE_WEEKLY",
                end: reset
            ),
            billingPeriodEnd: reset,
            productUsage: [GrokProductUsage(product: "GrokBuild")],
            subscriptionTier: nil
        ),
        subscriptionTier: "X Premium+"
    )

    #expect(response.displayPlan == "X Premium+")

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: response.displayPlan),
        now: Date(timeIntervalSince1970: 10)
    )

    #expect(state.providerID == ProviderID.grok)
    #expect(state.identity.plan == "X Premium+")
    #expect(state.windows.count == 1)
    #expect(state.windows[0].id == GrokWindowID.weekly)
    #expect(state.windows[0].usedPercent == 25)
    #expect(state.windows[0].remainingPercent == 75)
    #expect(state.windows[0].resetsAt == reset)
    #expect(state.sourceLabel == "cli-billing")
}

@Test func grokDisplayPlanIgnoresProductName() {
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 10,
            currentPeriod: nil,
            billingPeriodEnd: nil,
            productUsage: [GrokProductUsage(product: "GrokBuild")],
            subscriptionTier: nil
        ),
        subscriptionTier: nil
    )
    #expect(response.displayPlan == nil)
}

@Test func mapsGrokBillingUsingBillingPeriodEndFallback() {
    let reset = Date(timeIntervalSince1970: 1_900_000_000)
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 0,
            currentPeriod: nil,
            billingPeriodEnd: reset,
            productUsage: nil,
            subscriptionTier: nil
        ),
        subscriptionTier: nil
    )

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: nil)
    )

    #expect(state.windows[0].remainingPercent == 100)
    #expect(state.windows[0].resetsAt == reset)
}

@Test func prefersCurrentPeriodEndOverBillingPeriodEnd() {
    let weeklyEnd = Date(timeIntervalSince1970: 1_900_000_000)
    let billingEnd = Date(timeIntervalSince1970: 1_900_100_000)
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 12,
            currentPeriod: GrokUsagePeriod(end: weeklyEnd),
            billingPeriodEnd: billingEnd
        ),
        subscriptionTier: nil
    )

    #expect(response.resetsAt == weeklyEnd)
    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: nil)
    )
    #expect(state.windows[0].resetsAt == weeklyEnd)
}

/// Omitted `creditUsagePercent` is usage 0 (protobuf JSON default), independent
/// of whether period fields are present.
@Test func omittedCreditUsagePercentDefaultsToZeroUsed() {
    let reset = Date(timeIntervalSince1970: 1_900_000_000)
    let withPeriod = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 0,
            currentPeriod: GrokUsagePeriod(
                type: "USAGE_PERIOD_TYPE_WEEKLY",
                end: reset
            ),
            billingPeriodEnd: reset
        ),
        subscriptionTier: "X Premium+"
    )
    let withoutPeriod = GrokBillingResponse(
        config: GrokBillingConfig(),
        subscriptionTier: nil
    )

    let full = withPeriod.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: withPeriod.displayPlan)
    )
    #expect(full.windows[0].usedPercent == 0)
    #expect(full.windows[0].remainingPercent == 100)
    #expect(full.windows[0].resetsAt == reset)

    let noPeriod = withoutPeriod.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: nil)
    )
    #expect(noPeriod.windows[0].usedPercent == 0)
    #expect(noPeriod.windows[0].remainingPercent == 100)
    #expect(noPeriod.windows[0].resetsAt == nil)
}

/// Live post-reset shape from cli-chat-proxy (no creditUsagePercent key).
@Test func decodesLivePostResetCreditsJSONAsFullPool() throws {
    let json = """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-07-24T07:56:58.473996+00:00",
          "end": "2026-07-31T07:56:58.473996+00:00"
        },
        "onDemandCap": { "val": 0 },
        "onDemandUsed": { "val": 0 },
        "isUnifiedBillingUser": true,
        "prepaidBalance": { "val": 0 },
        "topUpMethod": "TOP_UP_METHOD_SAVED_PAYMENT_METHOD",
        "billingPeriodStart": "2026-07-24T07:56:58.473996+00:00",
        "billingPeriodEnd": "2026-07-31T07:56:58.473996+00:00"
      },
      "subscriptionTier": "X Premium+"
    }
    """
    let data = Data(json.utf8)
    let response = try GrokBillingCoding.makeDecoder()
        .decode(GrokBillingResponse.self, from: data)

    #expect(response.config.creditUsagePercent == 0)
    #expect(response.displayPlan == "X Premium+")
    #expect(response.config.currentPeriod?.type == "USAGE_PERIOD_TYPE_WEEKLY")

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: response.displayPlan)
    )
    #expect(state.windows[0].usedPercent == 0)
    #expect(state.windows[0].remainingPercent == 100)
    #expect(state.windows[0].resetsAt != nil)
    #expect(state.identity.plan == "X Premium+")
}

@Test func decodesCreditsJSONWithExplicitUsagePercent() throws {
    let json = """
    {
      "config": {
        "creditUsagePercent": 91.0,
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-07-17T07:56:58.473996+00:00",
          "end": "2026-07-24T07:56:58.473996+00:00"
        },
        "billingPeriodEnd": "2026-07-24T07:56:58.473996+00:00"
      },
      "subscriptionTier": "X Premium+"
    }
    """
    let response = try GrokBillingCoding.makeDecoder()
        .decode(GrokBillingResponse.self, from: Data(json.utf8))

    #expect(response.config.creditUsagePercent == 91)
    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: response.displayPlan)
    )
    #expect(state.windows[0].usedPercent == 91)
    #expect(state.windows[0].remainingPercent == 9)
}

@Test func loadsGrokAccessTokenFromAuthFile() throws {
    let tempHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-grok-auth-\(UUID().uuidString)", isDirectory: true)
    let grokDir = tempHome.appendingPathComponent(".grok", isDirectory: true)
    try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)

    let authURL = grokDir.appendingPathComponent("auth.json")
    let payload: [String: Any] = [
        "https://auth.x.ai::client": [
            "key": "test-access-token"
        ]
    ]
    try JSONSerialization.data(withJSONObject: payload).write(to: authURL)
    defer { try? FileManager.default.removeItem(at: tempHome) }

    let token = try GrokAuthStore(homeDirectory: tempHome).loadAccessToken()
    #expect(token == "test-access-token")
}

@Test func missingGrokAuthFileThrowsNotSignedIn() {
    let tempHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-grok-auth-missing-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempHome) }

    #expect(throws: GrokQuotaError.self) {
        try GrokAuthStore(homeDirectory: tempHome).loadAccessToken()
    }
}
