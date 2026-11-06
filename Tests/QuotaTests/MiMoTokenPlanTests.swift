import Foundation
import Testing
@testable import Quota

@Test func officialMiMoPlanMapsCreditsAndUTCReset() throws {
    let json = #"{"object":"token_plan","plan_code":"pro","period":{"end_at":"2027-09-21 23:59:59"},"quota":{"total_credits":10000000,"used_credits":1500000,"remaining_credits":8500000}}"#
    let plan = try JSONDecoder().decode(MiMoTokenPlanResponse.self, from: Data(json.utf8))
    let reset = try #require(MiMoPlanDetail(currentPeriodEnd: plan.period.end_at).resetDate(timeZone: TimeZone(secondsFromGMT: 0)!))
    let state = try plan.usageResponse.makeProviderState(identity: ProviderIdentity(displayName: "MiMo", plan: plan.plan_code), resetsAt: reset)
    #expect(state.windows[0].usedPercent == 15)
    #expect(state.windows[0].resetsAt == reset)
    #expect(ISO8601DateFormatter().string(from: reset) == "2027-09-21T23:59:59Z")
}

@Test func miMoAPIKeyEnvironmentOverridesCookie() throws {
    let store = MiMoAuthStore(environment: ["XIAOMI_MIMO_API_KEY": "tp-test"], keychainReader: { "old-cookie" })
    #expect(try store.loadAPIKey() == "tp-test")
}
