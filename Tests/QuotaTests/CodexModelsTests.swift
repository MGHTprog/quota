import Foundation
import Testing
@testable import Quota

@Test func mapsWindowsByDurationAndProducesBadges() throws {
    let response = GetAccountRateLimitsResponse(
        rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: 125,
                windowDurationMins: 60,
                resetsAt: 1_800_000_000
            ),
            secondary: RateLimitWindow(
                usedPercent: -10,
                windowDurationMins: 7 * 24 * 60,
                resetsAt: 1_900_000_000
            )
        ),
        rateLimitResetCredits: RateLimitResetCredits(availableCount: 3)
    )

    let state = try response.makeProviderState(
        identity: ProviderIdentity(displayName: "Codex", plan: "Pro"),
        now: Date(timeIntervalSince1970: 10)
    )

    #expect(state.providerID == ProviderID.codex)
    #expect(state.identity.displayName == "Codex")
    #expect(state.windows.count == 2)
    #expect(state.windows[0].id == CodexWindowID.fiveHour)
    #expect(state.windows[0].usedPercent == 100)
    #expect(state.windows[0].remainingPercent == 0)
    #expect(state.windows[1].id == CodexWindowID.weekly)
    #expect(state.windows[1].usedPercent == 0)
    #expect(state.windows[1].remainingPercent == 100)
    #expect(state.badges.count == 1)
    #expect(!state.badges[0].text.isEmpty)
    #expect(state.updatedAt == Date(timeIntervalSince1970: 10))
}

@Test func legacyPrimarySecondaryFallbackKeepsTwoSlots() throws {
    let response = GetAccountRateLimitsResponse(
        rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: 40,
                windowDurationMins: nil,
                resetsAt: nil
            ),
            secondary: nil
        ),
        rateLimitResetCredits: nil
    )

    let state = try response.makeProviderState(
        identity: ProviderIdentity(displayName: "Codex", plan: nil)
    )

    #expect(state.windows.count == 2)
    #expect(state.windows[0].isAvailable)
    #expect(!state.windows[1].isAvailable)
    #expect(state.badges == [])
}

@Test func throwsWhenAllWindowsAreMissing() {
    let response = GetAccountRateLimitsResponse(
        rateLimits: RateLimitSnapshot(primary: nil, secondary: nil),
        rateLimitResetCredits: nil
    )

    #expect(throws: (any Error).self) {
        try response.makeProviderState(
            identity: ProviderIdentity(displayName: "Codex", plan: nil)
        )
    }
}
