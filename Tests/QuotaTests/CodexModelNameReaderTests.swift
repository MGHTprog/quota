import Foundation
import Testing
@testable import Quota

@Test func recentModelUsesTurnTimestampAndSkipsApprovalReviewer() {
    let text = """
    {"type":"turn_context","timestamp":"2026-10-03T01:00:00Z","payload":{"model":"gpt-6.1-sol"}}
    {"type":"turn_context","timestamp":"2026-10-03T00:00:00Z","payload":{"model":"gpt-6-sol"}}
    {"type":"turn_context","timestamp":"2026-10-03T02:00:00Z","payload":{"model":"codex-auto-review"}}
    {"type":"event_msg","timestamp":"2026-10-03T03:00:00Z","payload":{"model":"not-a-turn"}}
    """
    #expect(CodexModelNameReader.latestModel(in: text)?.model == "gpt-6.1-sol")
    #expect(CodexModelNameReader.format("gpt-6.1-sol") == "GPT-6.1 Sol")
}

@Test func recentModelFallsBackWhenSessionHistoryIsAbsent() {
    let reader = CodexModelNameReader(home: URL(fileURLWithPath: "/nonexistent-quota-test"))
    #expect(reader.displayName(fallback: "GPT") == "GPT")
}
