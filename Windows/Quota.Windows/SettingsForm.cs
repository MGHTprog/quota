using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace Quota.Windows
{
    internal sealed class SettingsForm : Form
    {
        private readonly AppSettings working;
        private readonly CheckedListBox providers = new CheckedListBox();
        private readonly ComboBox proxyMode = new ComboBox();
        private readonly TextBox proxyUrl = new TextBox();
        private readonly ComboBox language = new ComboBox();
        private readonly CheckBox hotkeyEnabled = new CheckBox();
        private readonly ComboBox hotkey = new ComboBox();
        private readonly CheckBox notifications = new CheckBox();
        private readonly CheckBox floatingWindow = new CheckBox();
        private readonly TextBox mimoCookie = new TextBox();
        private readonly TextBox deepseekApiKey = new TextBox();
        private readonly string loadedMiMoCookie;
        private readonly string loadedDeepSeekApiKey;
        public AppSettings Value { get { return working; } }

        public SettingsForm(AppSettings source)
        {
            working = source.Clone();
            loadedMiMoCookie = MiMoCredentialStore.LoadSavedCookie();
            loadedDeepSeekApiKey = DeepSeekCredentialStore.LoadSavedApiKey();
            Text = L.SettingsText;
            ClientSize = new Size(510, 480);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 9F);

            var tabs = new TabControl { Dock = DockStyle.Top, Height = 420 };
            tabs.TabPages.Add(BuildProvidersTab());
            tabs.TabPages.Add(BuildConnectionTab());
            tabs.TabPages.Add(BuildGeneralTab());

            var save = new Button { Text = L.T("保存", "Save"), DialogResult = DialogResult.None, Location = new Point(414, 438), Width = 80 };
            var cancel = new Button { Text = L.T("取消", "Cancel"), DialogResult = DialogResult.Cancel, Location = new Point(326, 438), Width = 80 };
            save.Click += delegate { SaveAndClose(); };
            Controls.Add(tabs);
            Controls.Add(save);
            Controls.Add(cancel);
            AcceptButton = save;
            CancelButton = cancel;
        }

        private TabPage BuildProvidersTab()
        {
            var page = new TabPage(L.T("服务", "Providers"));
            page.Controls.Add(new Label { Text = L.T("选择显示的服务，并用上下按钮调整优先顺序。", "Select providers and change their priority."), Location = new Point(18, 18), AutoSize = true });
            providers.Location = new Point(20, 52);
            providers.Size = new Size(355, 180);
            providers.CheckOnClick = true;
            foreach (var id in working.ProviderOrder)
            {
                int index = providers.Items.Add(ProviderInfo.Name(id));
                providers.SetItemChecked(index, working.EnabledProviders.Contains(id));
            }
            var up = new Button { Text = L.T("上移", "Up"), Location = new Point(390, 75), Width = 80 };
            var down = new Button { Text = L.T("下移", "Down"), Location = new Point(390, 112), Width = 80 };
            up.Click += delegate { MoveSelected(-1); };
            down.Click += delegate { MoveSelected(1); };
            var cookieLabel = new Label { Text = "MiMo Cookie", Location = new Point(20, 246), AutoSize = true };
            mimoCookie.Location = new Point(118, 242);
            mimoCookie.Size = new Size(352, 23);
            mimoCookie.UseSystemPasswordChar = true;
            mimoCookie.Text = loadedMiMoCookie;
            var cookieHelp = new Label
            {
                Text = L.T(
                    "可粘贴 Cookie 值或完整请求头；使用 Windows 用户加密存储。",
                    "Paste a Cookie value or complete request headers; stored with Windows user encryption."),
                Location = new Point(20, 274), Size = new Size(450, 34), ForeColor = Color.DimGray
            };
            var deepseekLabel = new Label { Text = "DeepSeek API Key", Location = new Point(20, 316), AutoSize = true };
            deepseekApiKey.Location = new Point(148, 312);
            deepseekApiKey.Size = new Size(322, 23);
            deepseekApiKey.UseSystemPasswordChar = true;
            deepseekApiKey.Text = loadedDeepSeekApiKey;
            var deepseekHelp = new Label
            {
                Text = L.T(
                    "输入 DeepSeek API 密钥；使用 Windows 用户加密存储。",
                    "Enter DeepSeek API key; stored with Windows user encryption."),
                Location = new Point(20, 344), Size = new Size(450, 34), ForeColor = Color.DimGray
            };
            page.Controls.Add(providers);
            page.Controls.Add(up);
            page.Controls.Add(down);
            page.Controls.Add(cookieLabel);
            page.Controls.Add(mimoCookie);
            page.Controls.Add(cookieHelp);
            page.Controls.Add(deepseekLabel);
            page.Controls.Add(deepseekApiKey);
            page.Controls.Add(deepseekHelp);
            return page;
        }

        private TabPage BuildConnectionTab()
        {
            var page = new TabPage(L.T("代理", "Proxy"));
            page.Controls.Add(new Label { Text = L.T("代理模式", "Proxy mode"), Location = new Point(20, 30), AutoSize = true });
            proxyMode.DropDownStyle = ComboBoxStyle.DropDownList;
            proxyMode.Items.AddRange(new object[] { L.T("自动（使用系统代理）", "Automatic (system proxy)"), L.T("手动", "Manual"), L.T("关闭", "Disabled") });
            proxyMode.SelectedIndex = (int)working.ProxyMode;
            proxyMode.Location = new Point(140, 26);
            proxyMode.Width = 310;
            proxyMode.SelectedIndexChanged += delegate { proxyUrl.Enabled = proxyMode.SelectedIndex == (int)ProxyMode.Manual; };
            page.Controls.Add(new Label { Text = L.T("代理地址", "Proxy URL"), Location = new Point(20, 83), AutoSize = true });
            proxyUrl.Text = working.ProxyUrl;
            proxyUrl.Location = new Point(140, 79);
            proxyUrl.Width = 310;
            proxyUrl.Enabled = working.ProxyMode == ProxyMode.Manual;
            page.Controls.Add(new Label { Text = "http://127.0.0.1:7890", Location = new Point(140, 111), AutoSize = true, ForeColor = Color.DimGray });
            page.Controls.Add(proxyMode);
            page.Controls.Add(proxyUrl);
            return page;
        }

        private TabPage BuildGeneralTab()
        {
            var page = new TabPage(L.T("常规", "General"));
            page.Controls.Add(new Label { Text = L.T("语言", "Language"), Location = new Point(20, 28), AutoSize = true });
            language.DropDownStyle = ComboBoxStyle.DropDownList;
            language.Items.AddRange(new object[] { L.T("跟随系统", "System"), "简体中文", "English" });
            language.SelectedIndex = (int)working.Language;
            language.Location = new Point(140, 24);
            language.Width = 250;
            hotkeyEnabled.Text = L.T("启用全局快捷键", "Enable global hotkey");
            hotkeyEnabled.Checked = working.HotkeyEnabled;
            hotkeyEnabled.Location = new Point(20, 83);
            hotkeyEnabled.AutoSize = true;
            hotkey.Items.AddRange(new object[] { "Ctrl + Alt + Q", "Ctrl + Shift + Q", "Win + Alt + Q" });
            hotkey.DropDownStyle = ComboBoxStyle.DropDownList;
            hotkey.SelectedIndex = HotkeyIndex(working.HotkeyModifiers);
            hotkey.Location = new Point(220, 80);
            hotkey.Width = 170;
            floatingWindow.Text = L.T("显示桌面额度悬浮窗", "Show desktop quota widget");
            floatingWindow.Checked = working.FloatingWindowEnabled;
            floatingWindow.Location = new Point(20, 135);
            floatingWindow.AutoSize = true;
            notifications.Text = L.T("启用低额度通知", "Enable low-quota notifications");
            notifications.Checked = working.NotificationsEnabled;
            notifications.Location = new Point(20, 178);
            notifications.AutoSize = true;
            page.Controls.Add(language);
            page.Controls.Add(hotkeyEnabled);
            page.Controls.Add(hotkey);
            page.Controls.Add(floatingWindow);
            page.Controls.Add(notifications);
            return page;
        }

        private static int HotkeyIndex(int modifiers)
        {
            if (modifiers == 6) return 1;
            if (modifiers == 9) return 2;
            return 0;
        }

        private void MoveSelected(int delta)
        {
            int index = providers.SelectedIndex;
            int target = index + delta;
            if (index < 0 || target < 0 || target >= providers.Items.Count) return;
            bool check = providers.GetItemChecked(index);
            object item = providers.Items[index];
            providers.Items.RemoveAt(index);
            providers.Items.Insert(target, item);
            providers.SetItemChecked(target, check);
            providers.SelectedIndex = target;
        }

        private void SaveAndClose()
        {
            if (providers.CheckedItems.Count == 0)
            {
                MessageBox.Show(L.T("请至少启用一个服务。", "Enable at least one provider."), "Quota", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (proxyMode.SelectedIndex == (int)ProxyMode.Manual)
            {
                Uri uri;
                if (!Uri.TryCreate(proxyUrl.Text.Trim(), UriKind.Absolute, out uri))
                {
                    MessageBox.Show(L.T("请输入完整的代理地址。", "Enter a complete proxy URL."), "Quota", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
            }

            string cookie;
            try
            {
                cookie = MiMoCredentialStore.NormalizeCookie(mimoCookie.Text);
                if (cookie != loadedMiMoCookie) MiMoCredentialStore.SaveCookie(cookie);
            }
            catch (Exception error)
            {
                MessageBox.Show(
                    L.T("无法保存 MiMo Cookie：", "Could not save MiMo Cookie: ") + error.Message,
                    "Quota", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string apiKey;
            try
            {
                apiKey = DeepSeekCredentialStore.NormalizeApiKey(deepseekApiKey.Text);
                if (apiKey != loadedDeepSeekApiKey) DeepSeekCredentialStore.SaveApiKey(apiKey);
            }
            catch (Exception error)
            {
                MessageBox.Show(
                    L.T("无法保存 DeepSeek API 密钥：", "Could not save DeepSeek API key: ") + error.Message,
                    "Quota", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            working.ProviderOrder.Clear();
            foreach (string item in providers.Items)
            {
                var id = ProviderInfo.Parse(item);
                if (id.HasValue) working.ProviderOrder.Add(id.Value);
            }
            working.EnabledProviders.Clear();
            foreach (string item in providers.CheckedItems)
            {
                var id = ProviderInfo.Parse(item);
                if (id.HasValue) working.EnabledProviders.Add(id.Value);
            }
            working.ProxyMode = (ProxyMode)proxyMode.SelectedIndex;
            working.ProxyUrl = proxyUrl.Text.Trim();
            working.Language = (UiLanguage)language.SelectedIndex;
            working.HotkeyEnabled = hotkeyEnabled.Checked;
            working.HotkeyModifiers = hotkey.SelectedIndex == 1 ? 6 : hotkey.SelectedIndex == 2 ? 9 : 3;
            working.HotkeyKey = (int)Keys.Q;
            working.NotificationsEnabled = notifications.Checked;
            working.FloatingWindowEnabled = floatingWindow.Checked;
            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
