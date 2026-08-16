using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Quota.Windows
{
    internal interface IQuotaProvider
    {
        ProviderId Id { get; }
        Task<ProviderResult> FetchAsync(CancellationToken token);
        void Stop();
    }

    internal static class ProviderFactory
    {
        public static List<IQuotaProvider> Create(AppSettings settings)
        {
            return new List<IQuotaProvider>
            {
                new CodexProvider(settings),
                new ClaudeProvider(settings),
                new GrokProvider(settings),
                new MiMoProvider(settings),
                new DeepSeekProvider(settings)
            };
        }
    }

    internal static class WebClientFactory
    {
        public static HttpClient Create(AppSettings settings)
        {
            // Providers supply authentication explicitly. Disabling the handler's
            // CookieContainer ensures MiMo's copied console Cookie header is sent
            // unchanged instead of being replaced by an empty container.
            var handler = new HttpClientHandler { UseCookies = false };
            if (settings.ProxyMode == ProxyMode.Disabled)
            {
                handler.UseProxy = false;
            }
            else if (settings.ProxyMode == ProxyMode.Manual)
            {
                handler.UseProxy = true;
                handler.Proxy = new WebProxy(settings.ProxyUrl);
            }
            var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(25) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Quota-Windows/1.0");
            client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
            return client;
        }
    }

    internal sealed class CodexProvider : IQuotaProvider
    {
        private readonly AppSettings settings;
        private Process process;
        public ProviderId Id { get { return ProviderId.Codex; } }

        public CodexProvider(AppSettings settings) { this.settings = settings; }

        public async Task<ProviderResult> FetchAsync(CancellationToken token)
        {
            try { return ProviderResult.Success(await FetchStateAsync(token)); }
            catch (Exception ex) { Stop(); return ProviderResult.Failure(Id, ex); }
        }

        private async Task<ProviderState> FetchStateAsync(CancellationToken token)
        {
            string executable = LocateCodex();
            if (executable == null) throw new InvalidOperationException(L.T(
                "未找到 Codex CLI，请先安装 Codex 并确保 codex 在 PATH 中。",
                "Codex CLI was not found on PATH."));

            var info = CreateStartInfo(executable);
            ApplyProxyEnvironment(info);
            process = new Process { StartInfo = info, EnableRaisingEvents = true };
            if (!process.Start()) throw new InvalidOperationException(L.T("无法启动 Codex。", "Could not start Codex."));

            var stderr = process.StandardError.ReadToEndAsync();
            try
            {
                await RpcAsync(1, "initialize", new Dictionary<string, object>
                {
                    { "clientInfo", new Dictionary<string, object> { { "name", "Quota Windows" }, { "version", "1.0" } } },
                    { "capabilities", new Dictionary<string, object>() }
                }, token);

                object account = null;
                try { account = await RpcAsync(2, "account/read", new Dictionary<string, object>(), token); }
                catch { }
                var limits = await RpcAsync(3, "account/rateLimits/read", new Dictionary<string, object>(), token);
                return MapCodex(limits, account);
            }
            finally { Stop(); }
        }

        private static ProcessStartInfo CreateStartInfo(string executable)
        {
            bool commandScript = executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
                || executable.EndsWith(".bat", StringComparison.OrdinalIgnoreCase);
            var info = new ProcessStartInfo
            {
                FileName = commandScript ? Environment.GetEnvironmentVariable("ComSpec") : executable,
                Arguments = commandScript
                    ? "/d /s /c \"\"" + executable + "\" app-server --listen stdio://\""
                    : "app-server --listen stdio://",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            return info;
        }

        private void ApplyProxyEnvironment(ProcessStartInfo info)
        {
            if (settings.ProxyMode == ProxyMode.Manual)
            {
                info.EnvironmentVariables["HTTP_PROXY"] = settings.ProxyUrl;
                info.EnvironmentVariables["HTTPS_PROXY"] = settings.ProxyUrl;
                info.EnvironmentVariables["http_proxy"] = settings.ProxyUrl;
                info.EnvironmentVariables["https_proxy"] = settings.ProxyUrl;
            }
            else if (settings.ProxyMode == ProxyMode.Disabled)
            {
                foreach (var key in new[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy" })
                    info.EnvironmentVariables.Remove(key);
            }
        }

        private async Task<object> RpcAsync(int id, string method, object parameters, CancellationToken token)
        {
            var request = new Dictionary<string, object>
            {
                { "jsonrpc", "2.0" }, { "id", id }, { "method", method }, { "params", parameters }
            };
            await process.StandardInput.WriteLineAsync(Json.Stringify(request));
            await process.StandardInput.FlushAsync();

            var timeout = Task.Delay(TimeSpan.FromSeconds(20), token);
            while (true)
            {
                var read = process.StandardOutput.ReadLineAsync();
                if (await Task.WhenAny(read, timeout) != read)
                    throw new TimeoutException(L.T("Codex 请求超时。", "Codex request timed out."));
                var line = await read;
                if (line == null) throw new InvalidDataException(L.T("Codex 提前退出。", "Codex exited unexpectedly."));
                object root;
                try { root = Json.Parse(line); } catch { continue; }
                var responseId = Json.Number(root, "id");
                if (!responseId.HasValue || (int)responseId.Value != id) continue;
                var error = Json.Get(root, "error");
                if (error != null) throw new InvalidOperationException(Json.Text(error, "message") ?? "Codex RPC error");
                var result = Json.Get(root, "result");
                if (result == null) throw new InvalidDataException(L.T("Codex 返回了无效数据。", "Codex returned invalid data."));
                return result;
            }
        }

        internal static ProviderState MapCodex(object payload, object accountPayload)
        {
            var state = NewState(ProviderId.Codex, "app-server");
            var account = Json.Get(accountPayload, "account");
            state.Plan = Json.Text(account, "planType");
            var limits = Json.Get(payload, "rateLimits");
            var primary = Json.Get(limits, "primary");
            var secondary = Json.Get(limits, "secondary");
            AddCodexWindow(state, primary, true);
            AddCodexWindow(state, secondary, false);
            if (state.Windows.Count == 0) throw new InvalidDataException(L.T("额度响应缺少窗口数据。", "Rate-limit windows are missing."));
            state.Windows.Sort((a, b) => a.Id == "fiveHour" ? -1 : (b.Id == "fiveHour" ? 1 : 0));
            var credits = Json.Get(payload, "rateLimitResetCredits");
            var count = Json.Number(credits, "availableCount");
            if (count.HasValue) state.Badge = L.T("重置额度 ", "Reset credits ") + ((int)count.Value);
            return state;
        }

        private static void AddCodexWindow(ProviderState state, object raw, bool primary)
        {
            if (raw == null) return;
            var duration = Json.Number(raw, "windowDurationMins");
            bool weekly = duration.HasValue ? duration.Value > 1440 : !primary;
            var reset = Json.Number(raw, "resetsAt");
            state.Windows.Add(new QuotaWindow
            {
                Id = weekly ? "weekly" : "fiveHour",
                Title = weekly ? L.Weekly : L.FiveHour,
                UsedPercent = Clamp(Json.Number(raw, "usedPercent") ?? 0),
                ResetsAt = reset.HasValue ? (DateTime?)Epoch(reset.Value) : null
            });
        }

        private static string LocateCodex()
        {
            try
            {
                var info = new ProcessStartInfo("where.exe", "codex")
                {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true
                };
                using (var finder = Process.Start(info))
                {
                    string output = finder.StandardOutput.ReadToEnd();
                    finder.WaitForExit(3000);
                    return output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault(File.Exists);
                }
            }
            catch { return null; }
        }

        public void Stop()
        {
            var current = process;
            process = null;
            if (current == null) return;
            try { if (!current.HasExited) current.Kill(); } catch { }
            try { current.Dispose(); } catch { }
        }

        internal static ProviderState NewState(ProviderId id, string source)
        {
            return new ProviderState { ProviderId = id, DisplayName = ProviderInfo.Name(id), Source = source, UpdatedAt = DateTime.Now };
        }
        internal static double Clamp(double value) { return Math.Max(0, Math.Min(100, value)); }
        internal static DateTime Epoch(double seconds) { return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(seconds).ToLocalTime(); }
    }

    internal sealed class ClaudeProvider : IQuotaProvider
    {
        private readonly AppSettings settings;
        private HttpClient client;
        public ProviderId Id { get { return ProviderId.Claude; } }
        public ClaudeProvider(AppSettings settings) { this.settings = settings; }

        public async Task<ProviderResult> FetchAsync(CancellationToken token)
        {
            try
            {
                string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", ".credentials.json");
                if (!File.Exists(path)) throw new InvalidOperationException(L.T(
                    "Claude Code 未登录，请先运行 claude 并登录。", "Claude Code is not signed in."));
                var credentials = Json.Parse(File.ReadAllText(path));
                var oauth = Json.Get(credentials, "claudeAiOauth");
                string accessToken = Json.Text(oauth, "accessToken");
                if (String.IsNullOrWhiteSpace(accessToken)) throw new InvalidDataException(L.T("Claude 登录信息无效。", "Claude credentials are invalid."));
                var expiry = Json.Number(oauth, "expiresAt");
                if (expiry.HasValue && CodexProvider.Epoch(expiry.Value / 1000) <= DateTime.Now)
                    throw new InvalidOperationException(L.T("Claude Code 登录已过期，请运行一次 claude。", "Claude Code sign-in has expired."));

                client = WebClientFactory.Create(settings);
                using (var request = new HttpRequestMessage(HttpMethod.Get, "https://api.anthropic.com/api/oauth/usage"))
                {
                    request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                    request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
                    using (var response = await client.SendAsync(request, token))
                    {
                        string body = await response.Content.ReadAsStringAsync();
                        if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                            throw new InvalidOperationException(L.T("Claude Code 未登录或登录已过期。", "Claude authorization has expired."));
                        if (!response.IsSuccessStatusCode) throw new HttpRequestException("Claude HTTP " + (int)response.StatusCode);
                        var state = MapClaude(Json.Parse(body));
                        var plan = Json.Text(oauth, "subscriptionType");
                        state.Plan = String.IsNullOrWhiteSpace(plan) ? null : CultureInfo.CurrentCulture.TextInfo.ToTitleCase(plan);
                        return ProviderResult.Success(state);
                    }
                }
            }
            catch (Exception ex) { return ProviderResult.Failure(Id, ex); }
            finally { Stop(); }
        }

        internal static ProviderState MapClaude(object payload)
        {
            var state = CodexProvider.NewState(ProviderId.Claude, "oauth-usage");
            foreach (var raw in Json.Array(payload, "limits"))
            {
                string group = (Json.Text(raw, "group") ?? "").ToLowerInvariant();
                if (group != "session" && group != "weekly") continue;
                string scopeName = Json.Text(Json.Get(Json.Get(raw, "scope"), "model"), "display_name")
                    ?? Json.Text(Json.Get(Json.Get(raw, "scope"), "model"), "displayName");
                string id = group == "session" ? "session" : "weekly" + (String.IsNullOrWhiteSpace(scopeName) ? "" : "@" + scopeName);
                if (state.Windows.Any(x => x.Id == id)) continue;
                state.Windows.Add(new QuotaWindow
                {
                    Id = id,
                    Title = group == "session" ? L.FiveHour : L.Weekly,
                    Scope = scopeName,
                    UsedPercent = CodexProvider.Clamp(Json.Number(raw, "percent") ?? 0),
                    ResetsAt = Json.Date(raw, "resets_at") ?? Json.Date(raw, "resetsAt")
                });
            }
            if (state.Windows.Count == 0)
            {
                AddLegacy(state, Json.Get(payload, "five_hour") ?? Json.Get(payload, "fiveHour"), "session", L.FiveHour);
                AddLegacy(state, Json.Get(payload, "seven_day") ?? Json.Get(payload, "sevenDay"), "weekly", L.Weekly);
            }
            return state;
        }

        private static void AddLegacy(ProviderState state, object raw, string id, string title)
        {
            if (raw == null) return;
            state.Windows.Add(new QuotaWindow { Id = id, Title = title,
                UsedPercent = CodexProvider.Clamp(Json.Number(raw, "utilization") ?? 0),
                ResetsAt = Json.Date(raw, "resets_at") ?? Json.Date(raw, "resetsAt") });
        }

        public void Stop() { if (client != null) { client.Dispose(); client = null; } }
    }

    internal sealed class GrokProvider : IQuotaProvider
    {
        private readonly AppSettings settings;
        private HttpClient client;
        public ProviderId Id { get { return ProviderId.Grok; } }
        public GrokProvider(AppSettings settings) { this.settings = settings; }

        public async Task<ProviderResult> FetchAsync(CancellationToken token)
        {
            try
            {
                string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".grok", "auth.json");
                if (!File.Exists(path)) throw new InvalidOperationException(L.T("Grok 未登录，请先运行 grok login。", "Grok is not signed in."));
                string tokenValue = FindGrokToken(Json.Parse(File.ReadAllText(path)));
                if (String.IsNullOrWhiteSpace(tokenValue)) throw new InvalidDataException(L.T("Grok 登录信息无效。", "Grok credentials are invalid."));
                client = WebClientFactory.Create(settings);
                using (var request = new HttpRequestMessage(HttpMethod.Get, "https://cli-chat-proxy.grok.com/v1/billing?format=credits"))
                {
                    request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokenValue);
                    using (var response = await client.SendAsync(request, token))
                    {
                        string body = await response.Content.ReadAsStringAsync();
                        if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                            throw new InvalidOperationException(L.T("Grok 登录已过期。", "Grok authorization has expired."));
                        if (!response.IsSuccessStatusCode) throw new HttpRequestException("Grok HTTP " + (int)response.StatusCode);
                        return ProviderResult.Success(MapGrok(Json.Parse(body)));
                    }
                }
            }
            catch (Exception ex) { return ProviderResult.Failure(Id, ex); }
            finally { Stop(); }
        }

        private static string FindGrokToken(object root)
        {
            var map = Json.Object(root);
            if (map == null) return null;
            foreach (var entry in map.Values)
            {
                string key = Json.Text(entry, "key");
                if (!String.IsNullOrWhiteSpace(key)) return key;
            }
            return null;
        }

        internal static ProviderState MapGrok(object payload)
        {
            var state = CodexProvider.NewState(ProviderId.Grok, "cli-billing");
            var config = Json.Get(payload, "config");
            state.Plan = Json.Text(payload, "subscriptionTier") ?? Json.Text(config, "subscriptionTier");
            var period = Json.Get(config, "currentPeriod");
            state.Windows.Add(new QuotaWindow
            {
                Id = "weekly", Title = L.Weekly,
                UsedPercent = CodexProvider.Clamp(Json.Number(config, "creditUsagePercent") ?? 0),
                ResetsAt = Json.Date(period, "end") ?? Json.Date(config, "billingPeriodEnd")
            });
            return state;
        }

        public void Stop() { if (client != null) { client.Dispose(); client = null; } }
    }

    internal sealed class MiMoProvider : IQuotaProvider
    {
        private readonly AppSettings settings;
        private HttpClient client;
        public ProviderId Id { get { return ProviderId.MiMo; } }
        public MiMoProvider(AppSettings settings) { this.settings = settings; }

        public async Task<ProviderResult> FetchAsync(CancellationToken token)
        {
            try
            {
                // MiMoCode account discovery is supplementary on Windows. The
                // console quota endpoint is authenticated by its web Cookie and
                // does not consume the tp-... API key or the discovered base URL.
                MiMoCredentialStore.TryValidateMiMoCodeAccount();
                string cookie = MiMoCredentialStore.LoadCookie();
                if (String.IsNullOrWhiteSpace(cookie))
                    throw new InvalidOperationException(L.T(
                        "缺少 MiMo 控制台 Cookie，请在“设置 → 服务”中填写。",
                        "MiMo console Cookie is missing. Add it in Settings > Providers."));

                client = WebClientFactory.Create(settings);
                object usage = await GetJsonAsync(
                    "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage", cookie, token, true);
                object detail = null;
                try
                {
                    detail = await GetJsonAsync(
                        "https://platform.xiaomimimo.com/api/v1/tokenPlan/detail", cookie, token, false);
                }
                catch { }
                return ProviderResult.Success(MapMiMo(usage, detail));
            }
            catch (Exception ex) { return ProviderResult.Failure(Id, ex); }
            finally { Stop(); }
        }

        private async Task<object> GetJsonAsync(string url, string cookie, CancellationToken token, bool required)
        {
            using (var request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.TryAddWithoutValidation("Cookie", cookie);
                request.Headers.Referrer = new Uri("https://platform.xiaomimimo.com/console/plan-manage");
                request.Headers.TryAddWithoutValidation("Origin", "https://platform.xiaomimimo.com");
                request.Headers.TryAddWithoutValidation("x-timezone", LocalTimeZoneId());
                using (var response = await client.SendAsync(request, token))
                {
                    string body = await response.Content.ReadAsStringAsync();
                    if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                        throw new InvalidOperationException(L.T(
                            "MiMo 控制台 Cookie 缺失或已过期。",
                            "MiMo console Cookie is missing or expired."));
                    if (!response.IsSuccessStatusCode)
                        throw new HttpRequestException("MiMo HTTP " + (int)response.StatusCode);
                    try { return Json.Parse(body); }
                    catch
                    {
                        if (required) throw new InvalidDataException(L.T("无法解析 MiMo 响应。", "Invalid MiMo response."));
                        return null;
                    }
                }
            }
        }

        private static string LocalTimeZoneId()
        {
            string id = TimeZoneInfo.Local.Id;
            switch (id)
            {
                case "China Standard Time": return "Asia/Shanghai";
                case "Tokyo Standard Time": return "Asia/Tokyo";
                case "Singapore Standard Time": return "Asia/Singapore";
                case "UTC": return "UTC";
                default: return id;
            }
        }

        internal static ProviderState MapMiMo(object payload, object detailPayload)
        {
            int code = (int)(Json.Number(payload, "code") ?? -1);
            if (code != 0)
            {
                string detail = Json.Text(payload, "message");
                throw new InvalidDataException("MiMo " + code + (String.IsNullOrWhiteSpace(detail) ? "" : ": " + detail));
            }

            var usage = Json.Get(Json.Get(payload, "data"), "usage");
            double total = 0;
            double used = 0;
            foreach (var item in Json.Array(usage, "items"))
            {
                string name = Json.Text(item, "name");
                if (name != "plan_total_token" && name != "compensation_total_token") continue;
                double limit = Math.Max(0, Json.Number(item, "limit") ?? 0);
                if (limit <= 0) continue;
                double itemUsed = Math.Max(0, Json.Number(item, "used") ?? 0);
                total += limit;
                used += Math.Min(itemUsed, limit);
            }
            if (total <= 0)
                throw new InvalidDataException(L.T("MiMo 响应缺少套餐额度数据。", "MiMo quota data is missing."));

            var state = CodexProvider.NewState(ProviderId.MiMo, "token-plan-console");
            var detailData = Json.Get(detailPayload, "data");
            if ((int)(Json.Number(detailPayload, "code") ?? -1) == 0)
                state.Plan = EmptyToNull(Json.Text(detailData, "planName"));
            double usedPercent = CodexProvider.Clamp(used / total * 100);
            double remaining = Math.Max(0, total - used);
            state.Badge = FormatCredits(remaining) + " Credits";
            state.Windows.Add(new QuotaWindow
            {
                Id = "token-plan",
                Title = L.T("套餐额度", "Token Plan"),
                UsedPercent = usedPercent,
                ResetsAt = ParseResetDate(Json.Text(detailData, "currentPeriodEnd"))
            });
            return state;
        }

        private static string EmptyToNull(string value)
        {
            return String.IsNullOrWhiteSpace(value) ? null : value.Trim();
        }

        private static DateTime? ParseResetDate(string value)
        {
            if (String.IsNullOrWhiteSpace(value)) return null;
            DateTime local;
            if (DateTime.TryParseExact(value.Trim(), "yyyy-MM-dd HH:mm:ss",
                CultureInfo.InvariantCulture, DateTimeStyles.None, out local))
                return DateTime.SpecifyKind(local, DateTimeKind.Local);
            DateTimeOffset iso;
            return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal, out iso) ? (DateTime?)iso.LocalDateTime : null;
        }

        private static string FormatCredits(double value)
        {
            double absolute = Math.Abs(value);
            double scaled;
            string suffix;
            if (absolute >= 1000000000) { scaled = value / 1000000000; suffix = "B"; }
            else if (absolute >= 1000000) { scaled = value / 1000000; suffix = "M"; }
            else if (absolute >= 1000) { scaled = value / 1000; suffix = "K"; }
            else return Math.Round(value).ToString("0", CultureInfo.InvariantCulture);
            string format = scaled >= 100 ? "0" : "0.#";
            return scaled.ToString(format, CultureInfo.InvariantCulture) + suffix;
        }

        public void Stop() { if (client != null) { client.Dispose(); client = null; } }
    }

    internal sealed class DeepSeekProvider : IQuotaProvider
    {
        private readonly AppSettings settings;
        private HttpClient client;
        public ProviderId Id { get { return ProviderId.DeepSeek; } }
        public DeepSeekProvider(AppSettings settings) { this.settings = settings; }

        public async Task<ProviderResult> FetchAsync(CancellationToken token)
        {
            try
            {
                string apiKey = LoadApiKey();
                if (String.IsNullOrWhiteSpace(apiKey))
                    throw new InvalidOperationException(L.T(
                        "未找到 DeepSeek API 密钥。请设置 DEEPSEEK_API_KEY 环境变量或创建 ~/.deepseek/api_key 文件。",
                        "DeepSeek API key not found. Set DEEPSEEK_API_KEY environment variable or create ~/.deepseek/api_key file."));

                client = WebClientFactory.Create(settings);
                using (var request = new HttpRequestMessage(HttpMethod.Get, "https://api.deepseek.com/user/balance"))
                {
                    request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
                    using (var response = await client.SendAsync(request, token))
                    {
                        string body = await response.Content.ReadAsStringAsync();
                        if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                            throw new InvalidOperationException(L.T(
                                "DeepSeek API 密钥无效或已过期。",
                                "DeepSeek API key is invalid or expired."));
                        if (!response.IsSuccessStatusCode) throw new HttpRequestException("DeepSeek HTTP " + (int)response.StatusCode);
                        return ProviderResult.Success(MapDeepSeek(Json.Parse(body)));
                    }
                }
            }
            catch (Exception ex) { return ProviderResult.Failure(Id, ex); }
            finally { Stop(); }
        }

        private static string LoadApiKey()
        {
            return DeepSeekCredentialStore.LoadApiKey();
        }

        internal static ProviderState MapDeepSeek(object payload)
        {
            var state = CodexProvider.NewState(ProviderId.DeepSeek, "api-balance");
            bool isAvailable = Json.Bool(payload, "is_available") ?? true;
            
            var balanceInfos = Json.Array(payload, "balance_infos");
            if (balanceInfos != null && balanceInfos.Length > 0)
            {
                var first = balanceInfos[0];
                string currency = Json.Text(first, "currency") ?? "CNY";
                string totalBalanceStr = Json.Text(first, "total_balance") ?? "0";
                string grantedBalanceStr = Json.Text(first, "granted_balance") ?? "0";
                string toppedUpBalanceStr = Json.Text(first, "topped_up_balance") ?? "0";
                
                double totalBalance, grantedBalance, toppedUpBalance;
                Double.TryParse(totalBalanceStr, NumberStyles.Any, CultureInfo.InvariantCulture, out totalBalance);
                Double.TryParse(grantedBalanceStr, NumberStyles.Any, CultureInfo.InvariantCulture, out grantedBalance);
                Double.TryParse(toppedUpBalanceStr, NumberStyles.Any, CultureInfo.InvariantCulture, out toppedUpBalance);
                
                string symbol = currency == "CNY" ? "¥" : "$";
                state.Badge = symbol + FormatMoney(totalBalance);
                state.Plan = currency;
                
                state.Windows.Add(new QuotaWindow
                {
                    Id = "balance",
                    Title = L.T("余额", "Balance"),
                    UsedPercent = 0,
                    Available = isAvailable,
                    ResetsAt = null,
                    Scope = FormatBalanceDetail(totalBalance, grantedBalance, toppedUpBalance, symbol)
                });
            }
            
            if (state.Windows.Count == 0)
            {
                state.Windows.Add(new QuotaWindow
                {
                    Id = "balance",
                    Title = L.T("余额", "Balance"),
                    UsedPercent = 0,
                    Available = false,
                    ResetsAt = null
                });
            }
            
            return state;
        }

        private static string FormatBalanceDetail(double total, double granted, double toppedUp, string symbol)
        {
            return String.Format("{0}{1} (赠送: {0}{2}, 充值: {0}{3})",
                symbol, FormatMoney(total), FormatMoney(granted), FormatMoney(toppedUp));
        }

        private static string FormatMoney(double value)
        {
            return value.ToString("N2", CultureInfo.InvariantCulture);
        }

        private static string FormatCredits(double value)
        {
            double absolute = Math.Abs(value);
            double scaled;
            string suffix;
            if (absolute >= 1000000000) { scaled = value / 1000000000; suffix = "B"; }
            else if (absolute >= 1000000) { scaled = value / 1000000; suffix = "M"; }
            else if (absolute >= 1000) { scaled = value / 1000; suffix = "K"; }
            else return Math.Round(value).ToString("0.##", CultureInfo.InvariantCulture);
            string format = scaled >= 100 ? "0" : "0.#";
            return scaled.ToString(format, CultureInfo.InvariantCulture) + suffix;
        }

        public void Stop() { if (client != null) { client.Dispose(); client = null; } }
    }
}
