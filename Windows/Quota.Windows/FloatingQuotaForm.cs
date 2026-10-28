using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace Quota.Windows
{
    internal sealed class FloatingQuotaForm : Form
    {
        private readonly Action openMainWindow;
        private readonly Action refresh;
        private readonly Action openSettings;
        private readonly Action hideWidget;
        private readonly Action exitApplication;
        private readonly Action<Point> positionChanged;
        private readonly ContextMenuStrip menu;
        private AppSettings settings;
        private IDictionary<ProviderId, ProviderResult> results;
        private bool dragging;
        private bool moved;
        private Point dragOrigin;
        private Point windowOrigin;
        private readonly Timer rotationTimer = new Timer();
        private int rotationIndex;

        public FloatingQuotaForm(
            Action openMainWindow,
            Action refresh,
            Action openSettings,
            Action hideWidget,
            Action exitApplication,
            Action<Point> positionChanged)
        {
            this.openMainWindow = openMainWindow;
            this.refresh = refresh;
            this.openSettings = openSettings;
            this.hideWidget = hideWidget;
            this.exitApplication = exitApplication;
            this.positionChanged = positionChanged;

            Text = "Quota Floating Window";
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            ClientSize = new Size(250, 52);
            MinimumSize = MaximumSize = Size;
            BackColor = Color.FromArgb(32, 36, 43);
            Opacity = 0.96;
            AutoScaleMode = AutoScaleMode.Dpi;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);

            menu = new ContextMenuStrip();
            BuildMenu();
            ContextMenuStrip = menu;
            MouseDown += OnWidgetMouseDown;
            MouseMove += OnWidgetMouseMove;
            MouseUp += OnWidgetMouseUp;
            rotationTimer.Tick += delegate { AdvanceRotation(); };
            rotationTimer.Start();
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                const int WS_EX_TOOLWINDOW = 0x00000080;
                const int WS_EX_NOACTIVATE = 0x08000000;
                var value = base.CreateParams;
                value.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
                return value;
            }
        }

        private void BuildMenu()
        {
            menu.Items.Clear();
            menu.Items.Add(L.T("打开额度面板", "Open quota panel"), null, delegate { openMainWindow(); });
            menu.Items.Add(L.Refresh, null, delegate { refresh(); });
            menu.Items.Add(L.SettingsText, null, delegate { openSettings(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.T("隐藏悬浮窗", "Hide floating window"), null, delegate { hideWidget(); });
            menu.Items.Add(L.Quit, null, delegate { exitApplication(); });
        }

        public void UpdateData(AppSettings value, IDictionary<ProviderId, ProviderResult> providerResults)
        {
            settings = value;
            results = providerResults;
            if (settings != null && (rotationIndex >= settings.ProviderOrder.Count || !settings.EnabledProviders.Contains(settings.ProviderOrder[rotationIndex])))
                rotationIndex = settings.ProviderOrder.FindIndex(settings.EnabledProviders.Contains);
            ScheduleRotation();
            BuildMenu();
            Invalidate();
        }

        private void ScheduleRotation()
        {
            int[] seconds = { 8, 3, 1, 1, 1 };
            rotationTimer.Interval = seconds[Math.Max(0, Math.Min(rotationIndex, seconds.Length - 1))] * 1000;
        }

        private void AdvanceRotation()
        {
            if (settings == null || settings.ProviderOrder.Count == 0) return;
            for (int i = 0; i < settings.ProviderOrder.Count; i++)
            {
                rotationIndex = (rotationIndex + 1) % settings.ProviderOrder.Count;
                if (settings.EnabledProviders.Contains(settings.ProviderOrder[rotationIndex])) break;
            }
            ScheduleRotation();
            Invalidate();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) rotationTimer.Dispose();
            base.Dispose(disposing);
        }

        public void ShowAtSavedPosition(AppSettings value)
        {
            settings = value;
            if (value.FloatingWindowX >= 0 && value.FloatingWindowY >= 0)
            {
                var requested = new Rectangle(value.FloatingWindowX, value.FloatingWindowY, Width, Height);
                var screen = Screen.AllScreens.FirstOrDefault(x => x.WorkingArea.IntersectsWith(requested));
                if (screen != null)
                    Location = KeepInside(requested.Location, screen.WorkingArea);
                else
                    PositionAtDefaultLocation();
            }
            else
            {
                PositionAtDefaultLocation();
            }

            if (!Visible) Show();
            TopMost = true;
            Invalidate();
        }

        private void PositionAtDefaultLocation()
        {
            var area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Right - Width - 18, area.Bottom - Height - 18);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            using (var path = RoundedRectangle(new Rectangle(0, 0, Width, Height), 12))
            {
                var oldRegion = Region;
                Region = new Region(path);
                if (oldRegion != null) oldRegion.Dispose();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var background = new LinearGradientBrush(ClientRectangle,
                Color.FromArgb(42, 47, 56), Color.FromArgb(27, 31, 38), LinearGradientMode.Vertical))
                e.Graphics.FillRectangle(background, ClientRectangle);
            using (var border = new Pen(Color.FromArgb(92, 101, 115)))
            using (var outline = RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), 12))
                e.Graphics.DrawPath(border, outline);

            using (var titleFont = new Font("Segoe UI Semibold", 7.5F))
            using (var valueFont = new Font("Segoe UI Semibold", 12F))
            using (var white = new SolidBrush(Color.WhiteSmoke))
            using (var muted = new SolidBrush(Color.FromArgb(165, 175, 188)))
            {
                var enabled = settings == null
                    ? new List<ProviderId>()
                    : settings.ProviderOrder.Where(settings.EnabledProviders.Contains).ToList();
                if (enabled.Count == 0)
                {
                    e.Graphics.DrawString(L.NoData, valueFont, white, 12, 15);
                    return;
                }

                var current = settings.ProviderOrder[Math.Max(0, rotationIndex)];
                if (current == ProviderId.Codex)
                {
                    DrawCodexColumns(e.Graphics, titleFont, valueFont, white, muted);
                    return;
                }
                if (current == ProviderId.MiMo)
                {
                    DrawMiMo(e.Graphics, titleFont);
                    return;
                }
                enabled = new List<ProviderId> { current };
                float left = 10;
                float availableWidth = Width - 20;
                float columnWidth = availableWidth / enabled.Count;
                for (int index = 0; index < enabled.Count; index++)
                {
                    var id = enabled[index];
                    float x = left + index * columnWidth;
                    if (index > 0)
                    {
                        using (var divider = new Pen(Color.FromArgb(70, 78, 90)))
                            e.Graphics.DrawLine(divider, x, 8, x, Height - 8);
                    }
                    string heading = ProviderInfo.Name(id);
                    ProviderResult headingResult;
                    if (id == ProviderId.Codex && results != null && results.TryGetValue(id, out headingResult) && headingResult.IsSuccess && !String.IsNullOrEmpty(headingResult.State.Model))
                        heading += " · " + headingResult.State.Model;
                    e.Graphics.DrawString(heading, titleFont, muted, x + 6, 6);

                    ProviderResult result;
                    QuotaWindow window = null;
                    string badge = null;
                    if (results != null && results.TryGetValue(id, out result) && result.IsSuccess)
                    {
                        window = result.State.Windows.FirstOrDefault();
                        badge = result.State.Badge;
                        if (id == ProviderId.Codex && result.State.Windows.Count > 1)
                        {
                            var second = result.State.Windows[1];
                            e.Graphics.DrawString(window.Title + " " + Math.Round(window.RemainingPercent) + "%   " + second.Title + " " + Math.Round(second.RemainingPercent) + "%", titleFont, white, x + 6, 26);
                            continue;
                        }
                    }
                    if (window == null)
                    {
                        e.Graphics.DrawString("--", valueFont, white, x + 6, 22);
                        continue;
                    }

                    bool isMoney = window.Id == "balance";
                    if (isMoney && !String.IsNullOrWhiteSpace(badge))
                    {
                        using (var moneyFont = new Font("Segoe UI Semibold", 15F))
                            TextRenderer.DrawText(e.Graphics, badge, moneyFont, new Rectangle(10, 20, Width - 20, 28), Color.WhiteSmoke,
                                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
                    }
                    else
                    {
                        double remaining = window.RemainingPercent;
                        Color color = remaining < 5 ? Color.FromArgb(255, 91, 91)
                            : remaining < 20 ? Color.FromArgb(255, 174, 66)
                            : Color.FromArgb(80, 214, 142);
                        using (var valueBrush = new SolidBrush(color))
                            e.Graphics.DrawString(Math.Round(remaining) + "%", valueFont, valueBrush, x + 6, 22);
                    }
                }
            }
        }

        private void DrawMiMo(Graphics graphics, Font font)
        {
            ProviderResult result = null;
            var state = results != null && results.TryGetValue(ProviderId.MiMo, out result) && result.IsSuccess ? result.State : null;
            var flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
            if (state == null)
            {
                TextRenderer.DrawText(graphics, "MiMo", font, new Rectangle(10, 4, Width - 20, 20), Color.WhiteSmoke, flags);
                TextRenderer.DrawText(graphics, result == null ? L.Loading : result.Error, font, new Rectangle(10, 25, Width - 20, 20), Color.LightCoral, flags);
                return;
            }
            var window = state == null ? null : state.Windows.FirstOrDefault();
            string expiry = window != null && window.ResetsAt.HasValue ? window.ResetsAt.Value.ToString("yyyy-MM-dd HH:mm") : "--";
            string usage = window != null && window.UsedAmount.HasValue && window.TotalAmount.HasValue
                ? window.UsedAmount.Value.ToString("N0") + " / " + window.TotalAmount.Value.ToString("N0") : "--";
            string percent = window == null ? "--" : Math.Round(window.RemainingPercent) + "%";
            TextRenderer.DrawText(graphics, "MiMo  " + L.T("到期 ", "Expires ") + expiry, font, new Rectangle(8, 3, Width - 78, 21), Color.WhiteSmoke, flags);
            using (var percentFont = new Font("Segoe UI Semibold", 18F))
                TextRenderer.DrawText(graphics, percent, percentFont, new Rectangle(Width - 78, 3, 70, Height - 6), Color.FromArgb(80, 214, 142),
                    TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
            using (var usageFont = new Font("Segoe UI Semibold", 6.5F))
                TextRenderer.DrawText(graphics, L.T("用量 ", "Usage ") + usage, usageFont, new Rectangle(8, 25, Width - 86, 20), Color.WhiteSmoke, flags);
        }

        private void DrawCodexColumns(Graphics graphics, Font titleFont, Font valueFont, Brush white, Brush muted)
        {
            ProviderResult result;
            ProviderState state = results != null && results.TryGetValue(ProviderId.Codex, out result) && result.IsSuccess ? result.State : null;
            var fiveHour = state == null ? null : state.Windows.FirstOrDefault(w => w.Id == "fiveHour");
            var weekly = state == null ? null : state.Windows.FirstOrDefault(w => w.Id == "weekly");
            string model = state == null || String.IsNullOrWhiteSpace(state.Model) ? "--" : FormatModel(state.Model);
            var columns = new[] { new Rectangle(6, 3, 112, Height - 6), new Rectangle(118, 3, 61, Height - 6), new Rectangle(179, 3, Width - 185, Height - 6) };
            using (var divider = new Pen(Color.FromArgb(70, 78, 90)))
            {
                graphics.DrawLine(divider, columns[1].Left, 8, columns[1].Left, Height - 8);
                graphics.DrawLine(divider, columns[2].Left, 8, columns[2].Left, Height - 8);
            }
            var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
            string plan = state == null || String.IsNullOrWhiteSpace(state.Plan) ? "--" : state.Plan;
            string header = "Codex " + plan;
            if (state != null && !String.IsNullOrWhiteSpace(state.Badge))
                header += " " + state.Badge.Replace("重置额度 ", "重置 ").Replace("Reset credits ", "Reset ");
            using (var headerFont = new Font("Segoe UI Semibold", 6.5F))
                TextRenderer.DrawText(graphics, header, headerFont, new Rectangle(columns[0].X, 4, columns[0].Width, 17), Color.FromArgb(165, 175, 188), flags);
            using (var modelFont = new Font("Segoe UI Semibold", 10F))
                TextRenderer.DrawText(graphics, model, modelFont, new Rectangle(columns[0].X, 20, columns[0].Width, 26), Color.WhiteSmoke, flags);
            DrawCodexLimit(graphics, titleFont, valueFont, columns[1], L.FiveHour, fiveHour);
            DrawCodexLimit(graphics, titleFont, valueFont, columns[2], L.Weekly, weekly);
        }

        private static void DrawCodexLimit(Graphics graphics, Font titleFont, Font valueFont, Rectangle bounds, string title, QuotaWindow window)
        {
            var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
            TextRenderer.DrawText(graphics, title, titleFont, new Rectangle(bounds.X, 4, bounds.Width, 17), Color.FromArgb(165, 175, 188), flags);
            double remaining = window == null ? 0 : window.RemainingPercent;
            Color color = window == null ? Color.WhiteSmoke : remaining < 5 ? Color.FromArgb(255, 91, 91) : remaining < 20 ? Color.FromArgb(255, 174, 66) : Color.FromArgb(80, 214, 142);
            TextRenderer.DrawText(graphics, window == null ? "--" : Math.Round(remaining) + "%", valueFont, new Rectangle(bounds.X, 20, bounds.Width, HeightForValue(bounds)), color, flags);
        }

        private static int HeightForValue(Rectangle bounds) { return Math.Max(1, bounds.Height - 17); }

        internal static string FormatModel(string model)
        {
            if (!model.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase)) return model;
            var parts = model.Substring(4).Split('-');
            for (int i = 1; i < parts.Length; i++)
                if (parts[i].Length > 0) parts[i] = Char.ToUpperInvariant(parts[i][0]) + parts[i].Substring(1);
            return "GPT" + String.Join(" ", parts);
        }

        private void OnWidgetMouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            dragging = true;
            moved = false;
            dragOrigin = Cursor.Position;
            windowOrigin = Location;
            Capture = true;
        }

        private void OnWidgetMouseMove(object sender, MouseEventArgs e)
        {
            if (!dragging) return;
            var cursor = Cursor.Position;
            int dx = cursor.X - dragOrigin.X;
            int dy = cursor.Y - dragOrigin.Y;
            if (Math.Abs(dx) > 3 || Math.Abs(dy) > 3) moved = true;
            Location = new Point(windowOrigin.X + dx, windowOrigin.Y + dy);
        }

        private void OnWidgetMouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left || !dragging) return;
            dragging = false;
            Capture = false;
            if (!moved)
            {
                openMainWindow();
                return;
            }

            var area = Screen.FromPoint(Cursor.Position).WorkingArea;
            Location = SnapToEdges(Location, area);
            positionChanged(Location);
        }

        private Point SnapToEdges(Point location, Rectangle area)
        {
            const int snapDistance = 24;
            var result = KeepInside(location, area);
            if (Math.Abs(result.X - area.Left) <= snapDistance) result.X = area.Left + 4;
            if (Math.Abs((result.X + Width) - area.Right) <= snapDistance) result.X = area.Right - Width - 4;
            if (Math.Abs(result.Y - area.Top) <= snapDistance) result.Y = area.Top + 4;
            if (Math.Abs((result.Y + Height) - area.Bottom) <= snapDistance) result.Y = area.Bottom - Height - 4;
            return result;
        }

        private Point KeepInside(Point location, Rectangle area)
        {
            return new Point(
                Math.Max(area.Left, Math.Min(area.Right - Width, location.X)),
                Math.Max(area.Top, Math.Min(area.Bottom - Height, location.Y)));
        }

        private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
        {
            int diameter = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
