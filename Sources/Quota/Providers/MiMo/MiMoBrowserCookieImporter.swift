import AppKit
import SweetCookieKit

/// Reads only MiMo authentication cookies from the system's default browser.
enum MiMoBrowserCookieImporter {
    static func loadCookie() throws -> String {
        let console = URL(string: "https://platform.xiaomimimo.com")!
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: console) else {
            throw MiMoQuotaError.sessionCookieMissing
        }
        let appName = appURL.deletingPathExtension().lastPathComponent
        guard let browser = Browser.allCases.first(where: {
            $0.appBundleName.caseInsensitiveCompare(appName) == .orderedSame
        }) else {
            throw MiMoQuotaError.sessionCookieMissing
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: ["platform.xiaomimimo.com", "xiaomimimo.com"])
        // Keep profiles separate: combining them could authenticate a different account.
        var lastError: Error?
        for store in client.stores(for: browser) {
            do {
                let cookies = try client.cookies(matching: query, in: store)
                if let header = header(from: cookies) { return header }
            } catch { lastError = error }
        }
        if let lastError { throw lastError }
        throw MiMoQuotaError.sessionCookieMissing
    }

    static func header(from cookies: [HTTPCookie], now: Date = Date()) -> String? {
        let required: Set<String> = ["api-platform_serviceToken", "userId"]
        let allowed = required.union(["api-platform_ph", "api-platform_slh"])
        var values: [String: HTTPCookie] = [:]
        for cookie in cookies {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard allowed.contains(cookie.name), !cookie.value.isEmpty,
                  domain == "xiaomimimo.com" || domain == "platform.xiaomimimo.com",
                  cookie.expiresDate.map({ $0 > now }) ?? true,
                  matchesPath(cookie.path, request: "/api/v1/tokenPlan/usage"),
                  matchesPath(cookie.path, request: "/api/v1/tokenPlan/detail") else { continue }
            if let previous = values[cookie.name], previous.path.count > cookie.path.count { continue }
            values[cookie.name] = cookie
        }
        guard required.isSubset(of: Set(values.keys)) else { return nil }
        return values.keys.sorted().compactMap { name in
            values[name].map { "\(name)=\($0.value)" }
        }.joined(separator: "; ")
    }

    private static func matchesPath(_ path: String, request: String) -> Bool {
        let path = path.isEmpty ? "/" : path
        return request == path || request.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }
}
