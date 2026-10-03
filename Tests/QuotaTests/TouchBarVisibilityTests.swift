import Testing
@testable import Quota

@Test func permanentTouchBarSwitchOverridesAndRestoresApplicationPolicy() {
    let policy = ActiveApplicationTouchBarPolicy()
    let browser = ActiveApplicationInfo(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
    #expect(!policy.shouldShow(for: browser))
    #expect(policy.shouldShow(for: browser, alwaysVisible: true))
    #expect(!policy.shouldShow(for: browser, alwaysVisible: false))
    #expect(policy.shouldShow(for: ActiveApplicationInfo(bundleIdentifier: nil, localizedName: nil), alwaysVisible: true))
}
