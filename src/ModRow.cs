using System;
using System.Drawing;
using System.Windows.Forms;

namespace TinkerlandsMods {
    internal sealed class ModRow : Panel {
        public readonly Mod Mod;
        public readonly InstalledMod Installed;
        public readonly bool InCatalog;
        public readonly string State;
        public bool HasUpdate { get { return State == Installer.UpdateAvailable; } }

        readonly CheckBox check = new CheckBox();
        readonly GameButton title;
        readonly GameButton update = new GameButton("Обновить");
        readonly Label version;
        readonly Label badge = Theme.Label("▲  Новая версия", Theme.Small, Theme.Gold);
        readonly Label activity = Theme.Label("", Theme.Small, Theme.Mint);
        readonly Meter meter = new Meter();
        bool selected;

        public bool Checked { get { return check.Checked; } set { check.Checked = value; } }
        public event EventHandler Pick;
        public event EventHandler UpdateMod;
        public event EventHandler CheckedChanged;

        public ModRow(Mod mod, InstalledMod installed, string state, bool inCatalog, ToolTip tips) {
            Mod = mod; Installed = installed; State = state; InCatalog = inCatalog;
            Height = 82; DoubleBuffered = true; BackColor = Theme.Panel;
            bool isInstalled = installed != null || state == Installer.ManualInstall;
            title = new GameButton(mod.title, quiet: true) {
                Font = isInstalled ? Theme.Body : Theme.Heading,
                ForeColor = isInstalled ? Theme.Installed : Theme.Paper,
                BackColor = Theme.Panel,
                TextAlign = ContentAlignment.MiddleLeft
            };
            string caption = state;
            if (installed != null) caption += "  ·  " + installed.version;
            if (HasUpdate) caption += "  →  " + mod.version;
            else if (installed == null && inCatalog) caption += "  ·  Версия в каталоге " + mod.version;
            version = Theme.Label(caption, Theme.Small, isInstalled ? Theme.Installed : Theme.Muted);
            version.Cursor = Cursors.Hand;
            badge.Visible = update.Visible = HasUpdate;
            activity.Visible = meter.Visible = false;
            check.Text = ""; check.AccessibleName = "Отметить мод «" + mod.title + "»";
            check.FlatStyle = FlatStyle.Flat; check.FlatAppearance.CheckedBackColor = Theme.Gold;
            check.ForeColor = Theme.Paper; check.BackColor = Color.Transparent; check.Cursor = Cursors.Hand;
            update.AccessibleName = "Обновить «" + mod.title + "»";
            Controls.AddRange(new Control[] { check, title, version, badge, update, activity, meter });

            Click += SelectMod;
            title.Click += SelectMod;
            version.Click += SelectMod;
            badge.Click += SelectMod;
            check.CheckedChanged += (s, e) => {
                if (Checked && check.Focused) SelectMod(s, e);
                if (CheckedChanged != null) CheckedChanged(this, e);
            };
            update.Click += (s, e) => { if (UpdateMod != null) UpdateMod(this, e); };
            if (!String.IsNullOrWhiteSpace(mod.description)) {
                string summary = mod.description.Trim();
                int firstLine = summary.IndexOfAny(new[] { '\r', '\n' });
                if (firstLine >= 0) summary = summary.Substring(0, firstLine);
                if (summary.Length > 225) summary = summary.Substring(0, 225).TrimEnd() + "…";
                tips.SetToolTip(this, summary);
                tips.SetToolTip(title, summary);
                tips.SetToolTip(version, summary);
                Disposed += (s, e) => { tips.SetToolTip(this, null); tips.SetToolTip(title, null); tips.SetToolTip(version, null); };
            }
        }

        void SelectMod(object sender, EventArgs e) { if (Pick != null) Pick(this, e); }

        public void SetSelected(bool value) {
            selected = value;
            title.BackColor = selected ? Theme.Raised : Theme.Panel;
            Invalidate(true);
        }

        public void SetBusy(bool value) { check.Enabled = update.Enabled = !value; }

        public void SetProgress(ModProgress progress, bool applyingPackage) {
            string label;
            switch (progress.Stage) {
                case ModStage.Queued: label = "В очереди"; break;
                case ModStage.Downloading: label = "Загрузка" + (progress.Percent.HasValue ? "  " + progress.Percent.Value + "%" : "…"); break;
                case ModStage.Checking: label = "Проверка файлов…"; break;
                case ModStage.Ready: label = "Файлы проверены"; break;
                case ModStage.Applying: label = applyingPackage ? "Применение…" : "Удаление…"; break;
                default: label = "Изменения сохранены"; break;
            }
            activity.ForeColor = Theme.Muted;
            activity.Text = label; activity.Visible = true;
            int? percent = progress.Percent;
            if (applyingPackage && progress.Stage == ModStage.Applying) percent = 100;
            meter.SetPercent(percent);
            meter.Visible = applyingPackage; Height = applyingPackage ? 116 : 105;
            PerformLayout();
        }

        public void SetResult(string message, Color ink) {
            activity.Text = message; activity.ForeColor = ink;
            activity.Visible = true; meter.Visible = false; Height = 105;
            PerformLayout();
        }

        protected override void OnLayout(LayoutEventArgs levent) {
            base.OnLayout(levent);
            if (title == null) return;
            int trailing = HasUpdate ? 150 : 12;
            check.SetBounds(14, 15, 23, 24);
            title.SetBounds(36, 11, Math.Max(0, Width - 36 - trailing), 31);
            version.SetBounds(43, 43, Math.Max(0, Width - 43 - trailing), 24);
            badge.SetBounds(Width - 134, 11, 120, 23);
            update.SetBounds(Width - 134, 37, 119, 31);
            activity.SetBounds(43, 72, Math.Max(0, Width - 57), 22);
            meter.SetBounds(43, 98, Math.Max(0, Width - 58), 8);
        }

        protected override void OnPaintBackground(PaintEventArgs e) {
            Theme.Frame(e.Graphics, ClientRectangle, selected ? Theme.Raised : Theme.Panel,
                selected ? Theme.Gold : Theme.Border, 4);
        }

        sealed class Meter : Control {
            int? percent;
            public Meter() { DoubleBuffered = true; TabStop = false; AccessibleRole = AccessibleRole.ProgressBar; }

            public void SetPercent(int? value) {
                percent = value; AccessibleName = value.HasValue ? "Загрузка " + value.Value + "%" : "Ход установки";
                Invalidate();
            }

            protected override void OnPaint(PaintEventArgs e) {
                Theme.Fill(e.Graphics, Theme.Shadow, ClientRectangle);
                int pixels = Math.Max(0, Width - 2) * Math.Min(100, Math.Max(0, percent.GetValueOrDefault())) / 100;
                if (pixels > 0) Theme.Fill(e.Graphics, Theme.Gold, new Rectangle(1, 1, pixels, Math.Max(0, Height - 2)));
            }
        }
    }
}
