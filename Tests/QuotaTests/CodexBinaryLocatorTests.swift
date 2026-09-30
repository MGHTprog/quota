import Foundation
import Testing
@testable import Quota

@Test func usesNewChatGPTBundleLocationWhenCLIIsNotOnPath() {
    let oldLocation = URL(fileURLWithPath: "/definitely/missing/codex")
    let currentLocation = URL(fileURLWithPath: "/bin/sh")
    let locator = CodexBinaryLocator(
        bundledBinaryURLs: [oldLocation, currentLocation],
        cliPathResolver: { nil }
    )

    #expect(locator.locate() == currentLocation)
}
