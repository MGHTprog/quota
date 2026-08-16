using System;
using System.Collections.Generic;

namespace Quota.Windows
{
    internal static class MappingTests
    {
        public static int Main()
        {
            try
            {
                L.Settings = new AppSettings { Language = UiLanguage.English };
                TestCodex();
                TestClaude();
                TestGrokDefaults();
                TestMiMo();
                TestFloatingWindowSettings();
                Console.WriteLine("All mapping tests passed.");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        private static void TestCodex()
        {
            var payload = Json.Parse("{\"rateLimits\":{\"primary\":{\"usedPercent\":25,\"windowDurationMins\":300,\"resetsAt\":1800000000},\"secondary\":{\"usedPercent\":40,\"windowDurationMins\":10080}},\"rateLimitResetCredits\":{\"availableCount\":2}}");
            var account = Json.Parse("{\"account\":{\"planType\":\"plus\"}}");
            var state = CodexProvider.MapCodex(payload, account);
            Assert(state.Windows.Count == 2, "Codex window count");
            Assert(state.Windows[0].Id == "fiveHour", "Codex window classification");
            Assert(Math.Abs(state.Windows[1].RemainingPercent - 60) < 0.01, "Codex remaining percent");
            Assert(state.Badge.EndsWith("2"), "Codex reset credits");
        }

        private static void TestClaude()
        {
            var payload = Json.Parse("{\"limits\":[{\"group\":\"session\",\"percent\":12},{\"group\":\"weekly\",\"percent\":60,\"scope\":{\"model\":{\"display_name\":\"Sonnet\"}}}]}");
            var state = ClaudeProvider.MapClaude(payload);
            Assert(state.Windows.Count == 2, "Claude window count");
            Assert(state.Windows[1].Id == "weekly@Sonnet", "Claude scoped weekly pool");
            Assert(Math.Abs(state.Windows[0].RemainingPercent - 88) < 0.01, "Claude remaining percent");
        }

        private static void TestGrokDefaults()
        {
            var payload = Json.Parse("{\"config\":{\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\"}},\"subscriptionTier\":\"X Premium+\"}");
            var state = GrokProvider.MapGrok(payload);
            Assert(state.Windows.Count == 1, "Grok window count");
            Assert(Math.Abs(state.Windows[0].RemainingPercent - 100) < 0.01, "Grok omitted usage defaults to zero used");
            Assert(state.Plan == "X Premium+", "Grok plan");
        }

        private static void TestFloatingWindowSettings()
        {
            var settings = new AppSettings();
            Assert(settings.FloatingWindowEnabled, "Floating window enabled by default");
            settings.FloatingWindowX = 321;
            settings.FloatingWindowY = 654;
            var copy = settings.Clone();
            Assert(copy.FloatingWindowEnabled, "Floating window clone enabled state");
            Assert(copy.FloatingWindowX == 321 && copy.FloatingWindowY == 654,
                "Floating window clone position");
        }

        private static void TestMiMo()
        {
            var payload = Json.Parse("{\"code\":0,\"data\":{\"usage\":{\"items\":[{\"name\":\"plan_total_token\",\"used\":1000000000,\"limit\":4100000000},{\"name\":\"compensation_total_token\",\"used\":100000000,\"limit\":300000000},{\"name\":\"month_total_token\",\"used\":99,\"limit\":100}]}}}");
            var detail = Json.Parse("{\"code\":0,\"data\":{\"planName\":\"Lite Monthly\",\"currentPeriodEnd\":\"2026-08-24 23:59:59\"}}");
            var state = MiMoProvider.MapMiMo(payload, detail);
            Assert(state.ProviderId == ProviderId.MiMo, "MiMo provider id");
            Assert(state.Windows.Count == 1 && state.Windows[0].Id == "token-plan", "MiMo token plan window");
            Assert(Math.Abs(state.Windows[0].UsedPercent - 25) < 0.0001, "MiMo combined quota percent");
            Assert(state.Badge == "3.3B Credits", "MiMo remaining credits badge");
            Assert(state.Plan == "Lite Monthly", "MiMo plan name");
            Assert(state.Windows[0].ResetsAt.HasValue, "MiMo reset time");
            Assert(MiMoCredentialStore.NormalizeCookie(" Cookie: a=1; b=2 ") == "a=1; b=2",
                "MiMo cookie normalization");
            Assert(MiMoCredentialStore.NormalizeCookie("Accept: application/json\r\nCookie: a=1; b=2\r\nOrigin: https://platform.xiaomimimo.com") == "a=1; b=2",
                "MiMo cookie extraction from request headers");
        }

        private static void Assert(bool condition, string name)
        {
            if (!condition) throw new InvalidOperationException("FAILED: " + name);
        }
    }
}
