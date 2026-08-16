using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Quota.Windows
{
    internal sealed class AppSettings
    {
        public ProxyMode ProxyMode = ProxyMode.Automatic;
        public string ProxyUrl = "";
        public UiLanguage Language = UiLanguage.System;
        public bool HotkeyEnabled = true;
        public int HotkeyModifiers = 3;
        public int HotkeyKey = 81;
        public bool NotificationsEnabled = true;
        public bool FloatingWindowEnabled = true;
        public int FloatingWindowX = -1;
        public int FloatingWindowY = -1;
        public readonly List<ProviderId> ProviderOrder = new List<ProviderId>();
        public readonly HashSet<ProviderId> EnabledProviders = new HashSet<ProviderId>();

        public AppSettings()
        {
            ProviderOrder.AddRange(new[] { ProviderId.Codex, ProviderId.Claude, ProviderId.Grok, ProviderId.MiMo });
            foreach (var id in ProviderOrder) EnabledProviders.Add(id);
        }

        public AppSettings Clone()
        {
            var copy = new AppSettings
            {
                ProxyMode = ProxyMode,
                ProxyUrl = ProxyUrl,
                Language = Language,
                HotkeyEnabled = HotkeyEnabled,
                HotkeyModifiers = HotkeyModifiers,
                HotkeyKey = HotkeyKey,
                NotificationsEnabled = NotificationsEnabled,
                FloatingWindowEnabled = FloatingWindowEnabled,
                FloatingWindowX = FloatingWindowX,
                FloatingWindowY = FloatingWindowY
            };
            copy.ProviderOrder.Clear();
            copy.ProviderOrder.AddRange(ProviderOrder);
            copy.EnabledProviders.Clear();
            foreach (var id in EnabledProviders) copy.EnabledProviders.Add(id);
            return copy;
        }
    }

    internal static class SettingsStore
    {
        private static readonly string DirectoryPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Quota");
        private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");

        public static AppSettings Load()
        {
            var result = new AppSettings();
            if (!File.Exists(FilePath)) return result;
            try
            {
                var root = Json.Parse(File.ReadAllText(FilePath));
                ProxyMode proxyMode;
                UiLanguage language;
                if (Enum.TryParse(Json.Text(root, "proxyMode"), true, out proxyMode)) result.ProxyMode = proxyMode;
                if (Enum.TryParse(Json.Text(root, "language"), true, out language)) result.Language = language;
                result.ProxyUrl = Json.Text(root, "proxyUrl") ?? "";
                result.HotkeyEnabled = Bool(root, "hotkeyEnabled", true);
                result.NotificationsEnabled = Bool(root, "notificationsEnabled", true);
                result.FloatingWindowEnabled = Bool(root, "floatingWindowEnabled", true);
                result.FloatingWindowX = (int)(Json.Number(root, "floatingWindowX") ?? -1);
                result.FloatingWindowY = (int)(Json.Number(root, "floatingWindowY") ?? -1);
                result.HotkeyModifiers = (int)(Json.Number(root, "hotkeyModifiers") ?? 3);
                result.HotkeyKey = (int)(Json.Number(root, "hotkeyKey") ?? 81);

                var order = Json.Array(root, "providerOrder").Select(x => ProviderInfo.Parse(Convert.ToString(x)))
                    .Where(x => x.HasValue).Select(x => x.Value).Distinct().ToList();
                foreach (ProviderId id in Enum.GetValues(typeof(ProviderId))) if (!order.Contains(id)) order.Add(id);
                if (order.Count > 0)
                {
                    result.ProviderOrder.Clear();
                    result.ProviderOrder.AddRange(order);
                }

                var enabled = Json.Array(root, "enabledProviders").Select(x => ProviderInfo.Parse(Convert.ToString(x)))
                    .Where(x => x.HasValue).Select(x => x.Value).ToList();
                result.EnabledProviders.Clear();
                foreach (var id in enabled.Take(5)) result.EnabledProviders.Add(id);
                if (result.EnabledProviders.Count == 0) result.EnabledProviders.Add(ProviderId.Codex);
            }
            catch { return new AppSettings(); }
            return result;
        }

        private static bool Bool(object root, string key, bool fallback)
        {
            var raw = Json.Get(root, key);
            return raw == null ? fallback : Convert.ToBoolean(raw);
        }

        public static void Save(AppSettings settings)
        {
            Directory.CreateDirectory(DirectoryPath);
            var data = new Dictionary<string, object>
            {
                { "proxyMode", settings.ProxyMode.ToString() },
                { "proxyUrl", settings.ProxyUrl ?? "" },
                { "language", settings.Language.ToString() },
                { "hotkeyEnabled", settings.HotkeyEnabled },
                { "hotkeyModifiers", settings.HotkeyModifiers },
                { "hotkeyKey", settings.HotkeyKey },
                { "notificationsEnabled", settings.NotificationsEnabled },
                { "floatingWindowEnabled", settings.FloatingWindowEnabled },
                { "floatingWindowX", settings.FloatingWindowX },
                { "floatingWindowY", settings.FloatingWindowY },
                { "providerOrder", settings.ProviderOrder.Select(ProviderInfo.Key).ToArray() },
                { "enabledProviders", settings.ProviderOrder.Where(settings.EnabledProviders.Contains)
                    .Select(ProviderInfo.Key).ToArray() }
            };
            File.WriteAllText(FilePath, Json.Stringify(data));
        }
    }
}
