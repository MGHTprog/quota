import Foundation
import Testing
@testable import Quota

private let sampleUsageJSON = """
{
  "five_hour": {"utilization": 3.0, "resets_at": "2026-07-26T14:20:00.015140+00:00"},
  "seven_day": null,
  "limits": [
    {
      "kind": "session",
      "group": "session",
      "percent": 3,
      "severity": "normal",
      "resets_at": "2026-07-26T14:20:00.015140+00:00",
      "scope": null,
      "is_active": true
    },
    {
      "kind": "weekly_scoped",
      "group": "weekly",
      "percent": 1,
      "severity": "normal",
      "resets_at": "2026-07-28T21:59:59.015443+00:00",
      "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
      "is_active": false
    }
  ]
}
"""

@Test func decodesClaudeUsagePayload() throws {
    let decoder = ClaudeUsageCoding.makeDecoder()
    let response = try decoder.decode(
        ClaudeUsageResponse.self,
        from: Data(sampleUsageJSON.utf8)
    )

    #expect(response.limits?.count == 2)
    #expect(response.limits?[0].group == "session")
    #expect(response.limits?[1].scopeDisplayName == "Fable")
    #expect(response.fiveHour?.utilization == 3.0)
}

@Test func mapsClaudeLimitsToWindows() throws {
    let decoder = ClaudeUsageCoding.makeDecoder()
    let response = try decoder.decode(
        ClaudeUsageResponse.self,
        from: Data(sampleUsageJSON.utf8)
    )

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Claude", plan: "Max"),
        now: Date(timeIntervalSince1970: 10)
    )

    #expect(state.providerID == ProviderID.claude)
    #expect(state.identity.plan == "Max")
    #expect(state.sourceLabel == "oauth-usage")
    #expect(state.windows.count == 2)

    #expect(state.windows[0].id == ClaudeWindowID.session)
    #expect(state.windows[0].usedPercent == 3)
    #expect(state.windows[0].remainingPercent == 97)
    #expect(state.windows[0].resetsAt != nil)

    #expect(state.windows[1].id == "weekly@Fable")
    #expect(state.windows[1].usedPercent == 1)
    #expect(state.windows[1].remainingPercent == 99)
    #expect(state.windows[1].localizedTitle.contains("Fable"))
}

@Test func claudeFallsBackToLegacyBuckets() {
    let reset = Date(timeIntervalSince1970: 1_900_000_000)
    var response = ClaudeUsageResponse()
    response.fiveHour = ClaudeUsageBucket(utilization: 42, resetsAt: reset)
    response.sevenDay = ClaudeUsageBucket(utilization: 7, resetsAt: reset)
    response.limits = []

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Claude", plan: nil)
    )

    #expect(state.windows.count == 2)
    #expect(state.windows[0].id == ClaudeWindowID.session)
    #expect(state.windows[0].remainingPercent == 58)
    #expect(state.windows[1].id == ClaudeWindowID.weekly)
    #expect(state.windows[1].remainingPercent == 93)
    #expect(state.windows[1].resetsAt == reset)
}

@Test func claudeSessionWindowSortsFirst() {
    var response = ClaudeUsageResponse()
    response.limits = [
        ClaudeUsageLimit(group: "weekly", percent: 10),
        ClaudeUsageLimit(group: "session", percent: 5)
    ]

    let state = response.makeProviderState(
        identity: ProviderIdentity(displayName: "Claude", plan: nil)
    )

    #expect(state.windows.map(\.id) == [ClaudeWindowID.session, ClaudeWindowID.weekly])
}

@Test func claudeCredentialsDisplayPlanIsCapitalized() throws {
    let json = """
    {"claudeAiOauth": {"accessToken": "sk-test", "expiresAt": 4102444800000, "subscriptionType": "max"}}
    """
    let credentials = try JSONDecoder().decode(
        ClaudeCredentials.self,
        from: Data(json.utf8)
    )
    #expect(credentials.displayPlan == "Max")
}

@Test func claudeAuthStoreThrowsWhenTokenExpired() throws {
    let json = """
    {"claudeAiOauth": {"accessToken": "sk-test", "expiresAt": 1000000, "subscriptionType": "max"}}
    """
    let store = ClaudeAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        keychainData: { Data(json.utf8) }
    )

    #expect(throws: ClaudeQuotaError.self) {
        _ = try store.loadCredentials(now: Date(timeIntervalSince1970: 2_000_000))
    }
}

@Test func claudeAuthStoreThrowsWhenNotSignedIn() {
    let store = ClaudeAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        keychainData: { nil }
    )

    #expect(throws: ClaudeQuotaError.self) {
        _ = try store.loadCredentials()
    }
}

@Test func claudeAuthStoreFallsBackToFileWhenKeychainDataIsCorrupt() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-auth-test-\(UUID().uuidString)")
    let claudeDir = home.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let json = """
    {"claudeAiOauth": {"accessToken": "sk-from-file", "expiresAt": 4102444800000, "subscriptionType": "max"}}
    """
    try Data(json.utf8).write(to: claudeDir.appendingPathComponent(".credentials.json"))

    let store = ClaudeAuthStore(
        homeDirectory: home,
        keychainData: { Data("not json".utf8) }
    )

    let credentials = try store.loadCredentials(now: Date(timeIntervalSince1970: 1_000))
    #expect(credentials.claudeAiOauth.accessToken == "sk-from-file")
}

@Test func claudeAuthStoreAcceptsValidKeychainCredentials() throws {
    let json = """
    {"claudeAiOauth": {"accessToken": "sk-test", "expiresAt": 4102444800000, "subscriptionType": "pro"}}
    """
    let store = ClaudeAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        keychainData: { Data(json.utf8) }
    )

    let credentials = try store.loadCredentials(now: Date(timeIntervalSince1970: 1_000))
    #expect(credentials.claudeAiOauth.accessToken == "sk-test")
    #expect(credentials.displayPlan == "Pro")
}
