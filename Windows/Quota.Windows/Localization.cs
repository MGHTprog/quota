using System.Globalization;

namespace Quota.Windows
{
    internal static class L
    {
        public static AppSettings Settings;

        public static bool Chinese
        {
            get
            {
                if (Settings != null && Settings.Language == UiLanguage.Chinese) return true;
                if (Settings != null && Settings.Language == UiLanguage.English) return false;
                return CultureInfo.CurrentUICulture.Name.StartsWith("zh");
            }
        }

        public static string T(string zh, string en) { return Chinese ? zh : en; }
        public static string Refresh { get { return T("刷新", "Refresh"); } }
        public static string SettingsText { get { return T("设置", "Settings"); } }
        public static string Quit { get { return T("退出", "Quit"); } }
        public static string All { get { return T("全部", "All"); } }
        public static string Remaining { get { return T("剩余", "Remaining"); } }
        public static string Reset { get { return T("重置", "Reset"); } }
        public static string FiveHour { get { return T("5小时", "5 hour"); } }
        public static string Weekly { get { return T("周限额", "Weekly"); } }
        public static string NoData { get { return T("暂无数据", "No data"); } }
        public static string Loading { get { return T("正在刷新…", "Refreshing..."); } }
    }
}
