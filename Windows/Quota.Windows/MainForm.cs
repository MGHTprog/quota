using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Quota.Windows
{
    internal sealed class MainForm : Form
    {
        private const int HotkeyId = 1001;
        private static readonly int TaskbarCreatedMessage = NativeMethods.RegisterWindowMessage("TaskbarCreated");
        private AppSettings settings;
        private List<IQuotaProvider> providers;
        private readonly Icon applicationIcon;
        private readonly NotifyIcon trayIcon;
        private readonly FloatingQuotaForm floatingWindow;
        private readonly FlowLayoutPanel providerTabs;
        private readonly FlowLayoutPanel cards;
        private readonly Label statusLabel;
        private readonly Button refreshButton;
        private readonly Button settingsButton;
        private readonly System.Windows.Forms.Timer refreshTimer;
        private readonly Dictionary<ProviderId, ProviderResult> results = new Dictionary<ProviderId, ProviderResult>();
        private readonly HashSet<string> notifiedThresholds = new HashSet<string>();
        private CancellationTokenSource refreshCancellation;
        private ProviderId? filter;
        private bool exiting;

        public MainForm()
        {
            settings = SettingsStore.Load();
            L.Settings = settings;
            providers = ProviderFactory.Create(settings);

            Text = "Quota";
            ClientSize = new Size(430, 520);
            MinimumSize = new Size(390, 360);
            MaximumSize = new Size(520, 760);
            StartPosition = FormStartPosition.Manual;
            FormBorderStyle = FormBorderStyle.SizableToolWindow;
            ShowInTaskbar = false;
            applicationIcon = AppIcon.Load();
            Icon = applicationIcon;
            Font = new Font("Segoe UI", 9F);

            var header = new Panel { Dock = DockStyle.Top, Height = 48, Padding = new Padding(10, 8, 10, 6) };
            var title = new Label { Text = "Quota", AutoSize = true, Font = new Font("Segoe UI Semibold", 15F), Location = new Point(10, 10) };
            settingsButton = new Button { Text = "⚙", Width = 38, Height = 30, Dock = DockStyle.Right, FlatStyle = FlatStyle.Flat };
            refreshButton = new Button { Text = "↻", Width = 38, Height = 30, Dock = DockStyle.Right, FlatStyle = FlatStyle.Flat };
            settingsButton.FlatAppearance.BorderSize = refreshButton.FlatAppearance.BorderSize = 0;
            settingsButton.Click += delegate { OpenSettings(); };
            refreshButton.Click += async delegate { await RefreshAsync(); };
            header.Controls.Add(settingsButton);
            header.Controls.Add(refreshButton);
            header.Controls.Add(title);

            providerTabs = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 45, Padding = new Padding(10, 4, 6, 4), WrapContents = false };
            cards = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
                AutoScroll = true, Padding = new Padding(10, 8, 10, 8) };
            statusLabel = new Label { Dock = DockStyle.Bottom, Height = 30, Padding = new Padding(12, 7, 8, 0), ForeColor = Color.DimGray };

            Controls.Add(cards);
            Controls.Add(statusLabel);
            Controls.Add(providerTabs);
            Controls.Add(header);

            var menu = new ContextMenuStrip();
            menu.Items.Add(L.Refresh, null, async delegate { await RefreshAsync(); });
            menu.Items.Add(L.SettingsText, null, delegate { OpenSettings(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.Quit, null, delegate { ExitApplication(); });
            trayIcon = new NotifyIcon
            {
                Icon = applicationIcon,
                Text = "Quota",
                Visible = false,
                ContextMenuStrip = menu
            };
            trayIcon.MouseClick += delegate(object sender, MouseEventArgs e) { if (e.Button == MouseButtons.Left) ToggleWindow(); };

            floatingWindow = new FloatingQuotaForm(
                ShowMainWindow,
                RequestRefresh,
                OpenSettings,
                HideFloatingWindow,
                ExitApplication,
                SaveFloatingWindowPosition);
            RebuildTrayMenu();

            refreshTimer = new System.Windows.Forms.Timer { Interval = 120000 };
            refreshTimer.Tick += async delegate { await RefreshAsync(); };
            refreshTimer.Start();

            FormClosing += OnFormClosing;
            Deactivate += delegate { if (!ContainsFocus && Visible) Hide(); };
            Shown += async delegate
            {
                EnsureTrayIconVisible();
                BuildTabs();
                RegisterConfiguredHotkey();
                PositionNearTray();
                ApplyFloatingWindowSettings();
                // The 360-style widget is the primary surface on startup.
                // Keep the larger quota panel available on click/hotkey only.
                BeginInvoke(new Action(Hide));
                await RefreshAsync();
            };
        }

        private void BuildTabs()
        {
            providerTabs.SuspendLayout();
            providerTabs.Controls.Clear();
            providerTabs.Controls.Add(TabButton(L.All, null));
            foreach (var id in settings.ProviderOrder.Where(settings.EnabledProviders.Contains))
                providerTabs.Controls.Add(TabButton(ProviderInfo.Name(id), id));
            providerTabs.ResumeLayout();
        }

        private Button TabButton(string text, ProviderId? id)
        {
            var button = new Button { Text = text, AutoSize = true, Height = 31, FlatStyle = FlatStyle.Flat,
                BackColor = filter == id ? Color.FromArgb(220, 232, 246) : SystemColors.Control };
            button.FlatAppearance.BorderColor = filter == id ? Color.SteelBlue : Color.LightGray;
            button.Click += delegate { filter = id; BuildTabs(); RenderCards(); };
            return button;
        }

        private async Task RefreshAsync()
        {
            if (refreshCancellation != null) return;
            refreshCancellation = new CancellationTokenSource();
            refreshButton.Enabled = false;
            statusLabel.Text = L.Loading;
            try
            {
                var enabled = providers.Where(x => settings.EnabledProviders.Contains(x.Id)).ToList();
                var fetched = await Task.WhenAll(enabled.Select(x => x.FetchAsync(refreshCancellation.Token)));
                foreach (var result in fetched)
                {
                    results[result.ProviderId] = result;
                    if (result.IsSuccess) CheckNotifications(result.State);
                }
                statusLabel.Text = L.T("更新于 ", "Updated ") + DateTime.Now.ToString("HH:mm:ss");
                UpdateTrayTooltip();
                RenderCards();
                UpdateFloatingWindow();
            }
            catch (OperationCanceledException) { statusLabel.Text = L.T("刷新已取消", "Refresh cancelled"); }
            finally
            {
                refreshCancellation.Dispose();
                refreshCancellation = null;
                refreshButton.Enabled = true;
            }
        }

        private void RenderCards()
        {
            cards.SuspendLayout();
            cards.Controls.Clear();
            foreach (var id in settings.ProviderOrder.Where(settings.EnabledProviders.Contains))
            {
                if (filter.HasValue && filter.Value != id) continue;
                ProviderResult result;
                if (!results.TryGetValue(id, out result))
                    cards.Controls.Add(CreateMessageCard(id, L.Loading, false));
                else if (!result.IsSuccess)
                    cards.Controls.Add(CreateMessageCard(id, result.Error, true));
                else
                    cards.Controls.Add(CreateStateCard(result.State));
            }
            cards.ResumeLayout();
            UpdateFloatingWindow();
        }

        private Control CreateMessageCard(ProviderId id, string message, bool error)
        {
            var panel = CardPanel(ProviderInfo.Name(id), null);
            panel.Height = 88;
            panel.Controls.Add(new Label { Text = message, AutoEllipsis = true, ForeColor = error ? Color.Firebrick : Color.DimGray,
                Location = new Point(16, 48), Size = new Size(370, 25) });
            return panel;
        }

        private Control CreateStateCard(ProviderState state)
        {
            string detail = String.Join("  ", new[] { state.Plan, state.Badge }.Where(x => !String.IsNullOrWhiteSpace(x)));
            var panel = CardPanel(state.DisplayName, detail);
            int y = 48;
            if (state.Windows.Count == 0)
            {
                panel.Controls.Add(new Label { Text = L.NoData, Location = new Point(16, y), AutoSize = true, ForeColor = Color.DimGray });
                y += 30;
            }
            foreach (var window in state.Windows)
            {
                bool isMoney = window.Id == "balance";
                string title = window.Title + (String.IsNullOrWhiteSpace(window.Scope) ? "" : " · " + window.Scope);
                panel.Controls.Add(new Label { Text = title, Location = new Point(16, y), AutoSize = true, Font = new Font(Font, FontStyle.Bold) });
                if (!isMoney)
                    panel.Controls.Add(new Label { Text = L.Remaining + " " + Math.Round(window.RemainingPercent) + "%", Location = new Point(280, y), Size = new Size(105, 20), TextAlign = ContentAlignment.TopRight });
                y += 22;
                var bar = new QuotaBar { Location = new Point(16, y), Size = new Size(369, 9), Remaining = window.RemainingPercent };
                panel.Controls.Add(bar);
                y += 16;
                string reset = window.ResetsAt.HasValue ? L.Reset + " " + window.ResetsAt.Value.ToString("M/d HH:mm") : L.Reset + " --";
                panel.Controls.Add(new Label { Text = reset, Location = new Point(16, y), Size = new Size(369, 18), ForeColor = Color.DimGray });
                y += 26;
            }
            panel.Height = y + 7;
            return panel;
        }

        private Panel CardPanel(string title, string detail)
        {
            int width = Math.Max(350, cards.ClientSize.Width - 28);
            var panel = new Panel { Width = width, Height = 100, BackColor = Color.White, Margin = new Padding(0, 0, 0, 9), BorderStyle = BorderStyle.FixedSingle };
            panel.Controls.Add(new Label { Text = title, Location = new Point(15, 13), AutoSize = true, Font = new Font("Segoe UI Semibold", 12F) });
            if (!String.IsNullOrWhiteSpace(detail))
                panel.Controls.Add(new Label { Text = detail, Location = new Point(190, 17), Size = new Size(195, 20), TextAlign = ContentAlignment.TopRight, ForeColor = Color.DimGray });
            return panel;
        }

        private void CheckNotifications(ProviderState state)
        {
            if (!settings.NotificationsEnabled) return;
            foreach (var window in state.Windows)
            {
                // Skip money-based windows (like DeepSeek balance)
                if (window.Id == "balance") continue;
                int threshold = window.RemainingPercent < 5 ? 5 : window.RemainingPercent < 10 ? 10 : window.RemainingPercent < 20 ? 20 : 0;
                string prefix = ProviderInfo.Key(state.ProviderId) + ":" + window.Id + ":";
                if (window.RemainingPercent >= 50)
                {
                    notifiedThresholds.RemoveWhere(x => x.StartsWith(prefix, StringComparison.Ordinal));
                    continue;
                }
                if (threshold == 0) continue;
                string key = prefix + threshold;
                if (!notifiedThresholds.Add(key)) continue;
                trayIcon.BalloonTipTitle = state.DisplayName + " " + L.T("额度不足", "quota low");
                trayIcon.BalloonTipText = window.Title + " " + L.Remaining + " " + Math.Round(window.RemainingPercent) + "%";
                trayIcon.BalloonTipIcon = threshold <= 5 ? ToolTipIcon.Error : ToolTipIcon.Warning;
                trayIcon.ShowBalloonTip(5000);
            }
        }

        private void UpdateTrayTooltip()
        {
            var lines = new List<string> { "Quota" };
            foreach (var id in settings.ProviderOrder.Where(settings.EnabledProviders.Contains))
            {
                ProviderResult result;
                if (!results.TryGetValue(id, out result) || !result.IsSuccess || result.State.Windows.Count == 0) continue;
                var window = result.State.Windows[0];
                if (window.Id == "balance" && !String.IsNullOrWhiteSpace(result.State.Badge))
                    lines.Add(ProviderInfo.Name(id) + " " + result.State.Badge);
                else
                    lines.Add(ProviderInfo.Name(id) + " " + Math.Round(window.RemainingPercent) + "%");
            }
            string text = String.Join(" | ", lines);
            trayIcon.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private void OpenSettings()
        {
            using (var dialog = new SettingsForm(settings))
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                settings = dialog.Value;
                SettingsStore.Save(settings);
                L.Settings = settings;
                foreach (var provider in providers) provider.Stop();
                providers = ProviderFactory.Create(settings);
                results.Clear();
                BuildTabs();
                RebuildTrayMenu();
                RegisterConfiguredHotkey();
                ApplyFloatingWindowSettings();
                BeginInvoke(new Action(async delegate { await RefreshAsync(); }));
            }
        }

        private void RebuildTrayMenu()
        {
            var menu = trayIcon.ContextMenuStrip;
            menu.Items.Clear();
            menu.Items.Add(L.Refresh, null, async delegate { await RefreshAsync(); });
            menu.Items.Add(L.SettingsText, null, delegate { OpenSettings(); });
            menu.Items.Add(settings.FloatingWindowEnabled
                ? L.T("隐藏悬浮窗", "Hide floating window")
                : L.T("显示悬浮窗", "Show floating window"), null, delegate { ToggleFloatingWindow(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.Quit, null, delegate { ExitApplication(); });
        }

        private void ToggleWindow()
        {
            if (Visible) { Hide(); return; }
            PositionNearTray();
            Show();
            Activate();
        }

        private void ShowMainWindow()
        {
            if (!Visible)
            {
                PositionNearTray();
                Show();
            }
            Activate();
        }

        private async void RequestRefresh()
        {
            await RefreshAsync();
        }

        private void ApplyFloatingWindowSettings()
        {
            floatingWindow.UpdateData(settings, results);
            if (settings.FloatingWindowEnabled)
                floatingWindow.ShowAtSavedPosition(settings);
            else
                floatingWindow.Hide();
        }

        private void UpdateFloatingWindow()
        {
            floatingWindow.UpdateData(settings, results);
        }

        private void ToggleFloatingWindow()
        {
            settings.FloatingWindowEnabled = !settings.FloatingWindowEnabled;
            SettingsStore.Save(settings);
            ApplyFloatingWindowSettings();
            RebuildTrayMenu();
        }

        private void HideFloatingWindow()
        {
            if (!settings.FloatingWindowEnabled) return;
            settings.FloatingWindowEnabled = false;
            SettingsStore.Save(settings);
            floatingWindow.Hide();
            RebuildTrayMenu();
        }

        private void SaveFloatingWindowPosition(Point location)
        {
            settings.FloatingWindowX = location.X;
            settings.FloatingWindowY = location.Y;
            SettingsStore.Save(settings);
        }

        private void EnsureTrayIconVisible()
        {
            // Register only after the WinForms message loop owns a native handle.
            // Toggling visibility also refreshes a stale Shell_NotifyIcon entry.
            trayIcon.Visible = false;
            trayIcon.Visible = true;
        }

        private void PositionNearTray()
        {
            var area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Right - Width - 10, area.Bottom - Height - 10);
        }

        private void RegisterConfiguredHotkey()
        {
            NativeMethods.UnregisterHotKey(Handle, HotkeyId);
            if (settings.HotkeyEnabled)
                NativeMethods.RegisterHotKey(Handle, HotkeyId, (uint)settings.HotkeyModifiers, (uint)settings.HotkeyKey);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == TaskbarCreatedMessage && trayIcon != null)
                BeginInvoke(new Action(EnsureTrayIconVisible));
            if (m.Msg == NativeMethods.WM_HOTKEY && m.WParam.ToInt32() == HotkeyId) ToggleWindow();
            base.WndProc(ref m);
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (!exiting) { e.Cancel = true; Hide(); return; }
            refreshTimer.Stop();
            if (refreshCancellation != null) refreshCancellation.Cancel();
            foreach (var provider in providers) provider.Stop();
            floatingWindow.Close();
            floatingWindow.Dispose();
            NativeMethods.UnregisterHotKey(Handle, HotkeyId);
            trayIcon.Visible = false;
            trayIcon.Dispose();
            applicationIcon.Dispose();
        }

        private void ExitApplication() { exiting = true; Close(); }
    }

    internal sealed class QuotaBar : Control
    {
        private double remaining;
        public double Remaining { get { return remaining; } set { remaining = value; Invalidate(); } }
        public QuotaBar() { SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true); }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(Color.FromArgb(230, 230, 230));
            Color color = remaining < 5 ? Color.Firebrick : remaining < 20 ? Color.DarkOrange : Color.SeaGreen;
            using (var brush = new SolidBrush(color))
                e.Graphics.FillRectangle(brush, 0, 0, (int)(Width * Math.Max(0, Math.Min(100, remaining)) / 100.0), Height);
        }
    }
}
