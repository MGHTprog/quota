import Foundation
import Testing
@testable import Quota

@Test func automaticMiMoAuthenticationDoesNotRequireMiMoCode() throws {
    let store = MiMoAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:], keychainReader: { nil }, keychainWriter: { _ in },
        browserCookieReader: { "api-platform_serviceToken=test; userId=123" }
    )
    #expect(try store.loadSessionCookie() == "api-platform_serviceToken=test; userId=123")
}

@Test func browserCookiesExcludeOtherDomainsExpiredAndUnrelatedSecrets() {
    func cookie(_ name: String, domain: String = ".xiaomimimo.com", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: "test", .domain: domain, .path: "/"
        ]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }
    let token = cookie("api-platform_serviceToken")
    let user = cookie("userId")
    #expect(MiMoBrowserCookieImporter.header(from: [token, user, cookie("unrelated")])
        == "api-platform_serviceToken=test; userId=test")
    #expect(MiMoBrowserCookieImporter.header(from: [token, cookie("userId", domain: "example.com")]) == nil)
    #expect(MiMoBrowserCookieImporter.header(from: [token, cookie("userId", expires: .distantPast)]) == nil)
}
