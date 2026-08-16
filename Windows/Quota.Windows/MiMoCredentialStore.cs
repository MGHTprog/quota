using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace Quota.Windows
{
    internal static class MiMoCredentialStore
    {
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Quota.Windows.MiMo.Cookie.v1");
        private static readonly string CredentialPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Quota", "mimo-cookie.dat");

        public static string LoadCookie()
        {
            string environmentValue = Environment.GetEnvironmentVariable("XIAOMI_MIMO_SESSION_COOKIE");
            if (!String.IsNullOrWhiteSpace(environmentValue)) return NormalizeCookie(environmentValue);
            return LoadSavedCookie();
        }

        public static string LoadSavedCookie()
        {
            if (!File.Exists(CredentialPath)) return "";
            try
            {
                byte[] encrypted = File.ReadAllBytes(CredentialPath);
                byte[] plain = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
                return NormalizeCookie(Encoding.UTF8.GetString(plain));
            }
            catch { return ""; }
        }

        public static void SaveCookie(string value)
        {
            string normalized = NormalizeCookie(value);
            if (normalized.Length == 0)
            {
                if (File.Exists(CredentialPath)) File.Delete(CredentialPath);
                return;
            }

            string directory = Path.GetDirectoryName(CredentialPath);
            Directory.CreateDirectory(directory);
            byte[] plain = Encoding.UTF8.GetBytes(normalized);
            byte[] encrypted = ProtectedData.Protect(plain, Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(CredentialPath, encrypted);
        }

        internal static string NormalizeCookie(string value)
        {
            string result = (value ?? "").Trim();
            if (result.IndexOf('\r') >= 0 || result.IndexOf('\n') >= 0)
            {
                string cookieLine = result.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(x => x.Trim())
                    .FirstOrDefault(x => x.StartsWith("cookie:", StringComparison.OrdinalIgnoreCase));
                if (cookieLine == null)
                    throw new InvalidDataException(L.T(
                        "粘贴的请求头中没有 Cookie: 行。",
                        "The pasted request headers do not contain a Cookie: line."));
                result = cookieLine;
            }
            if (result.StartsWith("cookie:", StringComparison.OrdinalIgnoreCase))
                result = result.Substring("cookie:".Length).Trim();
            if (result.Length >= 2 && ((result[0] == '\'' && result[result.Length - 1] == '\'')
                || (result[0] == '"' && result[result.Length - 1] == '"')))
                result = result.Substring(1, result.Length - 2).Trim();
            if (result.Length > 0 && result.IndexOf('=') <= 0)
                throw new InvalidDataException(L.T(
                    "Cookie 内容无效，应包含名称和值。",
                    "The Cookie is invalid; it must contain a name and value."));
            return result;
        }

        public static bool TryValidateMiMoCodeAccount()
        {
            try { ValidateMiMoCodeAccount(); return true; }
            catch { return false; }
        }

        public static string FindMiMoCodeAuthFile()
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string xdg = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
            var candidates = new List<string>();
            if (!String.IsNullOrWhiteSpace(xdg)) candidates.Add(Path.Combine(xdg, "mimocode", "auth.json"));
            candidates.Add(Path.Combine(home, ".local", "share", "mimocode", "auth.json"));
            candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "mimocode", "auth.json"));
            candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "mimocode", "auth.json"));
            candidates.Add(Path.Combine(home, ".config", "mimocode", "auth.json"));
            return candidates.FirstOrDefault(File.Exists);
        }

        public static string ValidateMiMoCodeAccount()
        {
            string path = FindMiMoCodeAuthFile();
            if (path == null)
                throw new InvalidOperationException(L.T(
                    "MiMoCode 尚未登录小米，请先运行 mimo 并完成登录。",
                    "MiMoCode is not signed in to Xiaomi."));
            object root;
            try { root = Json.Parse(File.ReadAllText(path)); }
            catch { throw new InvalidDataException(L.T("无法读取 MiMoCode auth.json。", "MiMoCode auth.json is invalid.")); }
            var entry = Json.Get(root, "xiaomi");
            string key = Json.Text(entry, "key");
            if (String.IsNullOrWhiteSpace(key))
                throw new InvalidOperationException(L.T(
                    "MiMoCode 尚未登录小米，请先运行 mimo 并完成登录。",
                    "MiMoCode is not signed in to Xiaomi."));
            string baseUrl = Json.Text(Json.Get(entry, "metadata"), "base_url")
                ?? "https://token-plan-cn.xiaomimimo.com/v1";
            return baseUrl;
        }
    }
}
