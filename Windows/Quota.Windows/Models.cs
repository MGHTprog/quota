using System;
using System.Collections.Generic;
using System.Linq;

namespace Quota.Windows
{
    internal enum ProviderId { Codex, Claude, Grok, MiMo, DeepSeek }
    internal enum ProxyMode { Automatic, Manual, Disabled }
    internal enum UiLanguage { System, Chinese, English }

    internal sealed class QuotaWindow
    {
        public string Id;
        public string Title;
        public double UsedPercent;
        public DateTime? ResetsAt;
        public bool Available = true;
        public string Scope;

        public double RemainingPercent
        {
            get { return Math.Max(0, Math.Min(100, 100 - UsedPercent)); }
        }
    }

    internal sealed class ProviderState
    {
        public ProviderId ProviderId;
        public string DisplayName;
        public string Plan;
        public string Badge;
        public string Source;
        public DateTime UpdatedAt;
        public readonly List<QuotaWindow> Windows = new List<QuotaWindow>();
    }

    internal sealed class ProviderResult
    {
        public ProviderId ProviderId;
        public ProviderState State;
        public string Error;

        public bool IsSuccess { get { return State != null; } }

        public static ProviderResult Success(ProviderState state)
        {
            return new ProviderResult { ProviderId = state.ProviderId, State = state };
        }

        public static ProviderResult Failure(ProviderId id, Exception error)
        {
            var messages = new List<string>();
            Exception current = error;
            while (current != null && messages.Count < 5)
            {
                string message = (current.Message ?? "").Trim();
                if (message.Length > 0 && !messages.Contains(message)) messages.Add(message);
                current = current.InnerException;
            }
            string detail = String.Join(" → ", messages);
            if (detail.Length == 0) detail = error.GetType().Name;
            return new ProviderResult { ProviderId = id, Error = detail };
        }
    }

    internal static class ProviderInfo
    {
        public static string Name(ProviderId id)
        {
            switch (id)
            {
                case ProviderId.Codex: return "Codex";
                case ProviderId.Claude: return "Claude";
                case ProviderId.Grok: return "Grok";
                case ProviderId.MiMo: return "MiMo";
                case ProviderId.DeepSeek: return "DeepSeek";
                default: return id.ToString();
            }
        }

        public static string Key(ProviderId id) { return id.ToString().ToLowerInvariant(); }

        public static ProviderId? Parse(string value)
        {
            ProviderId result;
            return Enum.TryParse(value, true, out result) ? (ProviderId?)result : null;
        }
    }
}
