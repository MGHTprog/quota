using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Quota.Windows
{
    internal static class DeepSeekCredentialStore
    {
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Quota.Windows.DeepSeek.ApiKey.v1");
        private static readonly string CredentialPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Quota", "deepseek-api-key.dat");

        public static string LoadApiKey()
        {
            // Try environment variable first
            string envKey = Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY");
            if (!String.IsNullOrWhiteSpace(envKey)) return envKey.Trim();

            // Try config file (~/.deepseek/api_key)
            string homePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".deepseek", "api_key");
            if (File.Exists(homePath))
            {
                try
                {
                    string content = File.ReadAllText(homePath).Trim();
                    if (!String.IsNullOrWhiteSpace(content)) return content;
                }
                catch { }
            }

            // Try encrypted storage
            return LoadSavedApiKey();
        }

        public static string LoadSavedApiKey()
        {
            if (!File.Exists(CredentialPath)) return "";
            try
            {
                byte[] encrypted = File.ReadAllBytes(CredentialPath);
                byte[] plain = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(plain).Trim();
            }
            catch { return ""; }
        }

        public static void SaveApiKey(string value)
        {
            string normalized = NormalizeApiKey(value);
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

        internal static string NormalizeApiKey(string value)
        {
            string result = (value ?? "").Trim();
            // Remove any surrounding quotes
            if (result.Length >= 2 && ((result[0] == '\'' && result[result.Length - 1] == '\'')
                || (result[0] == '"' && result[result.Length - 1] == '"')))
                result = result.Substring(1, result.Length - 2).Trim();
            return result;
        }

        public static bool HasApiKey()
        {
            return !String.IsNullOrWhiteSpace(LoadApiKey());
        }
    }
}
