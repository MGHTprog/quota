import Foundation
import Testing
@testable import Quota

@Test func mapsGrokBillingToWeeklyWindow() throws {
    let reset = Date(timeIntervalSince1970: 1_900_000_000)
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: 25,
            currentPeriod: GrokUsagePeriod(end: reset),
            billingPeriodEnd: reset,
            productUsage: [GrokProductUsage(product: "GrokBuild")],
            subscriptionTier: nil
        ),
        subscriptionTier: "X Premium+"
    )

    #expect(response.displayPlan == "X Premium+")

    let state = try response.makeProviderState(
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

@Test func mapsGrokBillingUsingBillingPeriodEndFallback() throws {
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

    let state = try response.makeProviderState(
        identity: ProviderIdentity(displayName: "Grok", plan: nil)
    )

    #expect(state.windows[0].remainingPercent == 100)
    #expect(state.windows[0].resetsAt == reset)
}

@Test func throwsWhenGrokUsageDataIsMissing() {
    let response = GrokBillingResponse(
        config: GrokBillingConfig(
            creditUsagePercent: nil,
            currentPeriod: nil,
            billingPeriodEnd: nil,
            productUsage: nil,
            subscriptionTier: nil
        ),
        subscriptionTier: nil
    )

    #expect(throws: (any Error).self) {
        try response.makeProviderState(
            identity: ProviderIdentity(displayName: "Grok", plan: nil)
        )
    }
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
