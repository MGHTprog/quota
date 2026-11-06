import Foundation

/// Official Token Plan API, authenticated with a tp- key.
final class MiMoUsageClient {
    struct FetchResult {
        var response: MiMoUsageResponse
        var detail: MiMoPlanDetail?
        var account: MiMoCodeAccount
        var timeZone: TimeZone
    }
    private let session: URLSession
    private let authStore: MiMoAuthStore

    init(session: URLSession, authStore: MiMoAuthStore = .shared) {
        self.session = session
        self.authStore = authStore
    }
    convenience init(proxyConfiguration: ProxyConfiguration, authStore: MiMoAuthStore = .shared) {
        self.init(session: ProxiedURLSession.make(configuration: proxyConfiguration), authStore: authStore)
    }
    func fetchUsage(completion: @escaping (Result<FetchResult, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            do {
                let key = try authStore.loadAPIKey()
                let account = (try? authStore.loadMiMoCodeAccount()) ?? MiMoCodeAccount(
                    baseURL: URL(string: "https://token-plan-cn.xiaomimimo.com/v1")!)
                var request = URLRequest(url: account.baseURL.appendingPathComponent("platform/token_plan"))
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                session.dataTask(with: request) { data, response, error in
                    do {
                        if let error { throw error }
                        guard let http = response as? HTTPURLResponse else { throw MiMoQuotaError.invalidResponse }
                        if http.statusCode == 401 || http.statusCode == 403 { throw MiMoQuotaError.unauthorized }
                        guard (200..<300).contains(http.statusCode) else { throw MiMoQuotaError.requestFailed(http.statusCode) }
                        guard let data else { throw MiMoQuotaError.invalidResponse }
                        let plan = try JSONDecoder().decode(MiMoTokenPlanResponse.self, from: data)
                        completion(.success(FetchResult(response: plan.usageResponse,
                            detail: MiMoPlanDetail(planName: plan.plan_code, currentPeriodEnd: plan.period.end_at),
                            account: account, timeZone: TimeZone(secondsFromGMT: 0)!)))
                    } catch { completion(.failure(error)) }
                }.resume()
            } catch { completion(.failure(error)) }
        }
    }
}
