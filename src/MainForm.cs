using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TinkerlandsMods {
    sealed class MainForm : Form {
        readonly TextBox pathBox = new TextBox();
        readonly ListView list = new ListView();
        readonly Label description = new Label(), status = new Label(), release = new Label();
        readonly ProgressBar progress = new ProgressBar();
        readonly Button browse = new Button(), refresh = new Button(), apply = new Button(), remove = new Button(), updateAll = new Button(), selfUpdate = new Button();
        readonly string catalogPath, screenshot;
        CatalogResult source;
        bool busy;
        CancellationTokenSource cancellation;
        readonly Color background = Color.FromArgb(24, 27, 41), panel = Color.FromArgb(35, 39, 58), text = Color.FromArgb(237, 238, 246), muted = Color.FromArgb(168, 177, 201), accent = Color.FromArgb(116, 192, 163);
        public MainForm(string game, string catalog, string screenshotPath) {
            catalogPath = catalog; screenshot = screenshotPath;
            Text = "Tinkerlands Mods · " + Program.Version;
            BackColor = background; ForeColor = text; Font = new Font("Segoe UI", 10);
            Size = new Size(940, 755); MinimumSize = new Size(850, 660); StartPosition = FormStartPosition.CenterScreen;
            var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), RowCount = 9, ColumnCount = 1 };
            foreach (int height in new[] { 66, 28, 44, 38 }) root.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            foreach (int height in new[] { 76, 48, 28, 30 }) root.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
            Controls.Add(root);
            var header = new Panel { Dock = DockStyle.Fill };
            var title = new Label { Text = "TINKERLANDS", Font = new Font("Segoe UI", 23, FontStyle.Bold), ForeColor = accent, AutoSize = true, Location = new Point(0, 0) };
            header.Controls.Add(title); header.Controls.Add(new Label { Text = "Установка и обновление модов", ForeColor = muted, AutoSize = true, Location = new Point(3, 43) });
            root.Controls.Add(header, 0, 0);
            root.Controls.Add(new Label { Text = "ПАПКА ИГРЫ", ForeColor = muted, Dock = DockStyle.Fill, TextAlign = ContentAlignment.BottomLeft }, 0, 1);
            var paths = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Margin = new Padding(0, 5, 0, 3) };
            paths.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
            pathBox.Text = game; pathBox.ReadOnly = true; pathBox.Dock = DockStyle.Fill; pathBox.BackColor = panel; pathBox.ForeColor = text; pathBox.BorderStyle = BorderStyle.FixedSingle;
            ButtonStyle(browse, "Обзор…", false); paths.Controls.Add(pathBox); paths.Controls.Add(browse); root.Controls.Add(paths, 0, 2);
            var toolbar = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
            toolbar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); toolbar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145));
            release.Text = "Подключение к GitHub…"; release.ForeColor = muted; release.Dock = DockStyle.Fill; release.TextAlign = ContentAlignment.MiddleLeft;
            ButtonStyle(refresh, "Обновить список", false); toolbar.Controls.Add(release); toolbar.Controls.Add(refresh); root.Controls.Add(toolbar, 0, 3);
            list.Dock = DockStyle.Fill; list.View = View.Details; list.CheckBoxes = true; list.FullRowSelect = true; list.MultiSelect = false;
            list.HideSelection = false; list.BackColor = panel; list.ForeColor = text; list.BorderStyle = BorderStyle.None;
            list.Columns.Add("Мод", 260); list.Columns.Add("В каталоге", 105); list.Columns.Add("Установлен", 105); list.Columns.Add("Состояние", 230);
            root.Controls.Add(list, 0, 4);
            description.Dock = DockStyle.Fill; description.ForeColor = muted; description.Padding = new Padding(0, 12, 0, 0);
            description.Text = "Выберите мод, чтобы прочитать описание."; root.Controls.Add(description, 0, 5);
            var actions = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3 };
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42)); actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 30)); actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 28));
            ButtonStyle(apply, "Установить / обновить", true); ButtonStyle(updateAll, "Обновить все", false); ButtonStyle(remove, "Удалить выбранные", false);
            actions.Controls.Add(apply); actions.Controls.Add(updateAll); actions.Controls.Add(remove); root.Controls.Add(actions, 0, 6);
            progress.Dock = DockStyle.Fill; progress.Margin = new Padding(0, 8, 0, 5); root.Controls.Add(progress, 0, 7);
            var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3 };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 75));
            status.Dock = DockStyle.Fill; status.ForeColor = muted; status.TextAlign = ContentAlignment.MiddleLeft;
            ButtonStyle(selfUpdate, "Обновить установщик", false); selfUpdate.Visible = false;
            var github = new LinkLabel { Text = "GitHub ↗", Dock = DockStyle.Fill, LinkColor = accent, TextAlign = ContentAlignment.MiddleRight };
            github.LinkClicked += (s,e) => System.Diagnostics.Process.Start(Downloads.RepoUrl);
            footer.Controls.Add(status); footer.Controls.Add(selfUpdate); footer.Controls.Add(github); root.Controls.Add(footer, 0, 8);
            list.SelectedIndexChanged += (s,e) => { if (list.SelectedItems.Count != 0) description.Text = ((Mod)list.SelectedItems[0].Tag).description; };
            browse.Click += async (s,e) => {
                using (var picker = new FolderBrowserDialog { Description = "Папка с tinkerlands.exe", SelectedPath = pathBox.Text, ShowNewFolderButton = false }) {
                    if (picker.ShowDialog(this) != DialogResult.OK) return;
                    try { Game.Validate(picker.SelectedPath); pathBox.Text = picker.SelectedPath; Directory.CreateDirectory(Program.UserFolder); File.WriteAllText(Path.Combine(Program.UserFolder, "game-path.txt"), pathBox.Text); await RefreshList(); }
                    catch (Exception error) { ShowError(error); }
                }
            };
            refresh.Click += async (s,e) => await RefreshList();
            apply.Click += async (s,e) => await Apply(false, false);
            updateAll.Click += async (s,e) => await Apply(false, true);
            remove.Click += async (s,e) => await Apply(true, false);
            selfUpdate.Click += async (s,e) => {
                bool ok = await Job(() => SelfUpdate.Apply(source.catalog.installer, source.local_root, Report, cancellation.Token));
                if (ok) Close();
            };
            FormClosing += (s,e) => { if (busy) { e.Cancel = true; cancellation.Cancel(); status.Text = "Дождитесь завершения текущей операции…"; } };
            Shown += async (s,e) => {
                try { SelfUpdate.Confirm(System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName); }
                catch (IOException error) { Program.Log("Self-update cleanup: " + error.Message); }
                await RefreshList();
                if (screenshot != null) {
                    using (var bitmap = new Bitmap(Width, Height)) { DrawToBitmap(bitmap, new Rectangle(0,0,Width,Height)); bitmap.Save(screenshot, System.Drawing.Imaging.ImageFormat.Png); }
                    Close();
                }
            };
        }
        void ButtonStyle(Button button, string caption, bool primary) {
            button.Text = caption; button.Dock = DockStyle.Fill; button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderSize = 0;
            button.BackColor = primary ? accent : panel; button.ForeColor = primary ? background : text; button.Cursor = Cursors.Hand;
            button.Margin = new Padding(3);
        }
        void Report(string message, int percentage) {
            if (IsDisposed) return;
            BeginInvoke((Action)(() => { status.Text = message; progress.Value = Math.Max(0, Math.Min(100, percentage)); }));
        }
        void ShowError(Exception error) { Program.Log(error.ToString()); status.Text = error.Message; MessageBox.Show(this, error.Message, "Tinkerlands Mods", MessageBoxButtons.OK, MessageBoxIcon.Information); }
        async Task<bool> Job(Action work) {
            if (busy) return false;
            busy = true; cancellation = new CancellationTokenSource();
            foreach (var button in new[] {browse,refresh,apply,remove,updateAll,selfUpdate}) button.Enabled = false;
            try { await Task.Run(work); progress.Value = 100; return true; }
            catch (Exception error) { if (cancellation.IsCancellationRequested) status.Text = "Операция отменена."; else ShowError(error); return false; }
            finally { busy = false; cancellation.Dispose(); foreach (var button in new[] {browse,refresh,apply,remove,updateAll,selfUpdate}) button.Enabled = true; }
        }
        async Task RefreshList() {
            CatalogResult result = null;
            bool ok = await Job(() => result = Program.GetCatalog(catalogPath, ReportBytes, cancellation.Token));
            if (!ok) { release.Text = "Не удалось получить каталог. Можно повторить запрос."; return; }
            source = result; release.Text = "КАТАЛОГ · " + source.catalog.release;
            selfUpdate.Visible = SelfUpdate.Available(source.catalog.installer);
            RenderList();
        }
        void ReportBytes(long done, long total) { Report("Получение каталога", total > 0 ? (int)(done * 100 / total) : 0); }
        void RenderList() {
            list.Items.Clear();
            try {
                Installer manager = String.IsNullOrWhiteSpace(pathBox.Text) ? null : new Installer(pathBox.Text);
                var state = manager == null ? new InstalledState() : manager.ReadState();
                foreach (var mod in source.catalog.mods) {
                    var installed = state.mods.FirstOrDefault(m => m.id == mod.id);
                    var row = new ListViewItem(mod.title) { Tag = mod, Checked = false };
                    row.SubItems.Add(mod.version); row.SubItems.Add(installed == null ? "—" : installed.version);
                    row.SubItems.Add(manager == null ? "Укажите папку игры" : manager.Status(mod, state)); list.Items.Add(row);
                }
                foreach (var mod in state.mods.Where(m => !source.catalog.mods.Any(c => c.id == m.id))) {
                    var entry = new Mod { id = mod.id, title = mod.id, version = mod.version, description = "Эта установленная версия отсутствует в каталоге. Её можно удалить через учёт установщика." };
                    var row = new ListViewItem(entry.title) { Tag = entry }; row.SubItems.Add("—"); row.SubItems.Add(mod.version); row.SubItems.Add("Нет в каталоге"); list.Items.Add(row);
                }
                status.Text = manager == null ? "Игра не найдена — выберите папку вручную." : Game.Running() ? "Игра запущена. Для изменения модов закройте её." : "Готово. Отметьте нужные моды галочками.";
                if (!String.IsNullOrEmpty(source.notice)) status.Text = source.notice;
            } catch (Exception error) { status.Text = error.Message; }
        }
        async Task Apply(bool deleting, bool all) {
            if (source == null) return;
            try {
                var manager = new Installer(pathBox.Text); var state = manager.ReadState();
                string[] ids = all ? source.catalog.mods.Where(m => state.mods.Any(i => i.id == m.id) && manager.Status(m, state) == "Есть обновление").Select(m => m.id).ToArray()
                    : list.CheckedItems.Cast<ListViewItem>().Select(r => ((Mod)r.Tag).id).ToArray();
                if (ids.Length == 0) { status.Text = all ? "Обновлений установленных модов нет." : "Сначала отметьте моды галочками."; return; }
                bool ok = await Job(() => manager.Apply(source, deleting ? new string[0] : ids, deleting ? ids : new string[0], Report, cancellation.Token));
                RenderList(); if (ok) status.Text = deleting ? "Выбранные моды удалены." : "Моды установлены. Можно запускать игру.";
            } catch (Exception error) { ShowError(error); }
        }
    }
}
