using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TinkerlandsMods {
    sealed class MainForm : Form, IMessageFilter {
        readonly TextBox pathBox = new TextBox();
        readonly ScrollColumn cards = new ScrollColumn();
        readonly TableLayoutPanel catalogArea = new TableLayoutPanel();
        readonly Panel details = new Panel();
        readonly ScrollColumn detailText = new ScrollColumn();
        readonly ToolTip tips = new ToolTip { AutoPopDelay = 9000, InitialDelay = 550, ReshowDelay = 150 };
        readonly Label status = Theme.Label("Получение каталога…", Theme.Body, Theme.Muted);
        readonly Label release = Theme.Label("", Theme.Small, Theme.Muted);
        readonly Label empty = Theme.Label("Загрузка списка…", Theme.Body, Theme.Muted);
        readonly GameButton browse = new GameButton("Обзор…"), refresh = new GameButton("Обновить список"),
            apply = new GameButton("Установить / обновить", true), remove = new GameButton("Удалить выбранные"),
            updateAll = new GameButton("Обновить все"), selfUpdate = new GameButton("Обновить установщик");
        readonly Dictionary<string,ModRow> rows = new Dictionary<string,ModRow>();
        readonly string catalogPath, screenshot;
        CatalogResult source;
        Installer gameFolder;
        CancellationTokenSource cancellation;
        string selectedId;
        bool busy;

        public MainForm(string game, string catalog, string screenshotPath) {
            catalogPath = catalog; screenshot = screenshotPath;
            Text = "Tinkerlands Mods · " + Program.Version;
            BackColor = Theme.Background; ForeColor = Theme.Text; Font = Theme.Body;
            Size = new Size(1090, 736); MinimumSize = new Size(910, 580);
            StartPosition = FormStartPosition.CenterScreen; DoubleBuffered = true;

            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(22, 17, 22, 11) };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 109));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 61));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            Controls.Add(layout);
            layout.Controls.Add(new GameBanner { Dock = DockStyle.Fill, Margin = Padding.Empty }, 0, 0);
            layout.Controls.Add(GameFolder(game), 0, 1);
            layout.Controls.Add(BuildCatalogArea(), 0, 2);

            var actionBar = new FlowLayoutPanel { Dock = DockStyle.Fill, Margin = Padding.Empty, Padding = new Padding(0, 11, 0, 0), WrapContents = false };
            AddAction(actionBar, apply, 216);
            AddAction(actionBar, updateAll, 143);
            AddAction(actionBar, remove, 165);
            layout.Controls.Add(actionBar, 0, 3);
            layout.Controls.Add(BuildFooter(), 0, 4);

            browse.Click += async (s, e) => {
                using (var picker = new FolderBrowserDialog { Description = "Папка с tinkerlands.exe", SelectedPath = pathBox.Text, ShowNewFolderButton = false }) {
                    if (picker.ShowDialog(this) != DialogResult.OK) return;
                    try {
                        Game.Validate(picker.SelectedPath); pathBox.Text = picker.SelectedPath;
                        Directory.CreateDirectory(Program.UserFolder);
                        File.WriteAllText(Path.Combine(Program.UserFolder, "game-path.txt"), pathBox.Text);
                        await RefreshList();
                    } catch (Exception error) { ShowError(error); }
                }
            };
            refresh.Click += async (s, e) => await RefreshList();
            apply.Click += async (s, e) => await RunMods(CheckedRows().Select(row => row.Mod.id), false);
            remove.Click += async (s, e) => await RunMods(CheckedRows().Select(row => row.Mod.id), true);
            updateAll.Click += async (s, e) => await RunMods(rows.Values.Where(row => row.HasUpdate).Select(row => row.Mod.id), false);
            selfUpdate.Click += async (s, e) => {
                IProgress<int> download = new Progress<int>(percent => {
                    if (busy) ShowStatus("Загрузка установщика  " + percent + "%", Theme.Muted);
                });
                bool ok = await Job(token => SelfUpdate.Apply(source.catalog.installer, source.local_root,
                    (message, percent) => download.Report(percent), token));
                if (ok) Close();
            };
            FormClosing += (s, e) => {
                if (!busy) return;
                e.Cancel = true; cancellation.Cancel(); ShowStatus("Завершение текущей операции…", Theme.Muted);
            };
            FormClosed += (s, e) => { Application.RemoveMessageFilter(this); ClearRows(); tips.Dispose(); };
            Shown += async (s, e) => {
                Application.AddMessageFilter(this);
                ActiveControl = refresh;
                try { SelfUpdate.Confirm(Process.GetCurrentProcess().MainModule.FileName); }
                catch (IOException error) { Program.Log("Self-update cleanup: " + error.Message); }
                await RefreshList();
                if (screenshot != null) {
                    var first = cards.Items.OfType<ModRow>().FirstOrDefault();
                    if (first != null) SelectMod(first.Mod.id);
                    using (var bitmap = new Bitmap(Width, Height)) {
                        DrawToBitmap(bitmap, new Rectangle(0, 0, Width, Height)); bitmap.Save(screenshot, System.Drawing.Imaging.ImageFormat.Png);
                    }
                    Close();
                }
            };
            SetActions();
        }

        Control GameFolder(string game) {
            var folder = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 2, Margin = new Padding(0, 5, 0, 8) };
            folder.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            folder.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 114));
            folder.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 153));
            folder.RowStyles.Add(new RowStyle(SizeType.Absolute, 21));
            folder.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            var label = Theme.Label("Папка игры", Theme.Small, Theme.Muted); label.Dock = DockStyle.Fill;
            folder.Controls.Add(label, 0, 0);
            var pathFrame = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Panel, Padding = new Padding(10, 8, 9, 0), Margin = new Padding(0, 0, 0, 2) };
            pathBox.Text = game; pathBox.ReadOnly = true; pathBox.Dock = DockStyle.Fill; pathBox.BackColor = Theme.Panel;
            pathBox.ForeColor = Theme.Text; pathBox.BorderStyle = BorderStyle.None; pathBox.TabStop = false; pathBox.AccessibleName = "Папка игры";
            pathFrame.Controls.Add(pathBox); folder.Controls.Add(pathFrame, 0, 1);
            foreach (var button in new[] { browse, refresh }) { button.Dock = DockStyle.Fill; button.Margin = new Padding(8, 0, 0, 0); }
            folder.Controls.Add(browse, 1, 1); folder.Controls.Add(refresh, 2, 1);
            return folder;
        }

        Control BuildCatalogArea() {
            catalogArea.Dock = DockStyle.Fill; catalogArea.Margin = Padding.Empty;
            catalogArea.ColumnCount = 2; catalogArea.RowCount = 1;
            catalogArea.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            catalogArea.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 0));

            var catalogCard = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Shadow, Margin = Padding.Empty, Padding = new Padding(1) };
            var header = new Panel { Dock = DockStyle.Top, Height = 55 };
            var heading = Theme.Label("Доступные моды", Theme.Heading, Theme.Paper);
            heading.Dock = DockStyle.Left; heading.Width = 220; heading.Padding = new Padding(15, 0, 0, 0);
            release.Dock = DockStyle.Right; release.Width = 130; release.Padding = new Padding(0, 0, 13, 0);
            release.TextAlign = ContentAlignment.MiddleRight;
            header.Controls.Add(heading); header.Controls.Add(release);
            cards.Dock = DockStyle.Fill; cards.Padding = new Padding(11, 0, 11, 7);
            empty.Dock = DockStyle.Fill; empty.Padding = new Padding(15, 0, 15, 0); empty.TextAlign = ContentAlignment.TopLeft;
            catalogCard.Controls.Add(cards); catalogCard.Controls.Add(empty); catalogCard.Controls.Add(header);
            catalogArea.Controls.Add(catalogCard, 0, 0);

            details.Dock = DockStyle.Fill; details.Margin = new Padding(13, 0, 0, 0);
            details.BackColor = Theme.Panel; details.Padding = new Padding(17, 0, 15, 15);
            var detailHeader = new Panel { Dock = DockStyle.Top, Height = 51 };
            var detailLabel = Theme.Label("О моде", Theme.Small, Theme.Gold); detailLabel.Dock = DockStyle.Fill;
            var dismiss = new GameButton("×", quiet: true) { Dock = DockStyle.Right, Width = 40, Font = Theme.Heading,
                BackColor = Theme.Panel, AccessibleName = "Закрыть сведения о моде" };
            dismiss.Click += (s, e) => SelectMod(null);
            detailHeader.Controls.Add(detailLabel); detailHeader.Controls.Add(dismiss);
            detailText.Dock = DockStyle.Fill; detailText.BackColor = Theme.Panel; detailText.Padding = new Padding(0, 0, 8, 0);
            detailText.AccessibleName = "Описание и сведения о выбранном моде";
            details.Controls.Add(detailText); details.Controls.Add(detailHeader);
            details.Visible = false;
            catalogArea.Controls.Add(details, 1, 0);
            return catalogArea;
        }

        Control BuildFooter() {
            var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, Margin = Padding.Empty, BackColor = Theme.Panel, Padding = new Padding(11, 4, 3, 4) };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            status.Dock = DockStyle.Fill;
            selfUpdate.Size = new Size(173, 32); selfUpdate.Margin = Padding.Empty; selfUpdate.Visible = false;
            var github = new GameButton("GitHub ↗", quiet: true) { Dock = DockStyle.Fill, Margin = Padding.Empty, BackColor = Theme.Panel };
            github.Click += (s, e) => { try { Process.Start(Downloads.RepoUrl); } catch (Exception error) { ShowError(error); } };
            footer.Controls.Add(status, 0, 0); footer.Controls.Add(selfUpdate, 1, 0); footer.Controls.Add(github, 2, 0);
            return footer;
        }

        static void AddAction(FlowLayoutPanel parent, GameButton button, int width) {
            button.Size = new Size(width, 38); button.Margin = new Padding(0, 0, 8, 0); parent.Controls.Add(button);
        }

        void ClearRows() {
            foreach (var row in rows.Values) row.Dispose();
            rows.Clear();
        }

        IEnumerable<ModRow> CheckedRows() { return rows.Values.Where(row => row.Checked); }

        void SetActions() {
            var marked = CheckedRows().ToArray();
            bool ready = !busy && source != null && !String.IsNullOrWhiteSpace(pathBox.Text);
            browse.Enabled = refresh.Enabled = selfUpdate.Enabled = !busy;
            apply.Enabled = ready && marked.Length > 0 && marked.All(row => row.InCatalog);
            remove.Enabled = ready && marked.Length > 0 && marked.All(row => row.Installed != null);
            updateAll.Visible = rows.Values.Any(row => row.HasUpdate);
            updateAll.Enabled = ready && updateAll.Visible;
            foreach (var row in rows.Values) row.SetBusy(busy || !ready);
        }

        void ShowStatus(string message, Color ink) {
            status.Text = message; status.ForeColor = ink; tips.SetToolTip(status, message);
        }

        void ShowError(Exception error) { Program.Log(error.ToString()); ShowStatus(error.Message, Theme.Error); }

        async Task<bool> Job(Action<CancellationToken> work) {
            if (busy) return false;
            busy = true; cancellation = new CancellationTokenSource(); SetActions();
            try { await Task.Run(() => work(cancellation.Token)); return true; }
            catch (Exception error) {
                if (cancellation.IsCancellationRequested) ShowStatus("Операция отменена.", Theme.Muted);
                else ShowError(error);
                return false;
            } finally { busy = false; cancellation.Dispose(); SetActions(); }
        }

        async Task RefreshList() {
            if (busy) return;
            CatalogResult result = null;
            ShowStatus("Получение каталога с GitHub…", Theme.Muted);
            bool ok = await Job(token => result = Program.GetCatalog(catalogPath, null, token));
            if (!ok) { if (source == null) empty.Text = "Каталог недоступен. Нажмите «Обновить список», чтобы повторить."; return; }
            source = result; release.Text = source.catalog.release;
            selfUpdate.Visible = SelfUpdate.Available(source.catalog.installer);
            if (RenderList()) {
                string message = String.IsNullOrEmpty(pathBox.Text) ? "Укажите папку Tinkerlands." :
                    Game.Running() ? "Игра запущена. Закройте её перед изменением модов." : "Отметьте моды галочками или выберите мод, чтобы прочитать описание.";
                ShowStatus(source.notice ?? message, Theme.Muted);
            }
        }

        bool RenderList() {
            var marked = new HashSet<string>(CheckedRows().Select(row => row.Mod.id));
            int scroll = cards.Offset;
            cards.SuspendLayout();
            try {
                ClearRows();
                gameFolder = String.IsNullOrWhiteSpace(pathBox.Text) ? null : new Installer(pathBox.Text);
                var state = gameFolder == null ? new InstalledState() : gameFolder.ReadState();
                foreach (var mod in source.catalog.mods) {
                    var installed = state.mods.FirstOrDefault(item => item.id == mod.id);
                    AddRow(mod, installed, gameFolder == null ? "Укажите папку игры" : gameFolder.Status(mod, state), true, marked.Contains(mod.id));
                }
                foreach (var item in state.mods.Where(item => !rows.ContainsKey(item.id))) {
                    AddRow(new Mod { id = item.id, title = item.id, description = "Эта версия отсутствует в каталоге. Её можно удалить через установщик." },
                        item, "Нет в каталоге", false, marked.Contains(item.id));
                }
                SelectMod(selectedId);
                return true;
            } catch (Exception error) { ShowError(error); return false; }
            finally {
                empty.Text = "В каталоге пока нет модов."; empty.Visible = rows.Count == 0; cards.Visible = rows.Count > 0;
                cards.ResumeLayout(); cards.Arrange(); cards.Offset = scroll; SetActions();
            }
        }

        void AddRow(Mod mod, InstalledMod installed, string state, bool inCatalog, bool marked) {
            var row = new ModRow(mod, installed, state, inCatalog, tips) { Checked = marked, Margin = new Padding(0, 0, 0, 8) };
            row.Pick += (s, e) => SelectMod(mod.id);
            row.UpdateMod += async (s, e) => await RunMods(new[] { mod.id }, false);
            row.CheckedChanged += (s, e) => SetActions();
            row.Enter += (s, e) => cards.Reveal(row);
            rows.Add(mod.id, row); cards.Items.Add(row);
        }

        void SelectMod(string id) {
            ModRow row;
            if (selectedId != null && rows.TryGetValue(selectedId, out row)) row.SetSelected(false);
            selectedId = id != null && rows.ContainsKey(id) ? id : null;
            bool open = selectedId != null;
            details.Visible = open;
            catalogArea.ColumnStyles[0].Width = open ? 58 : 100;
            catalogArea.ColumnStyles[1].SizeType = open ? SizeType.Percent : SizeType.Absolute;
            catalogArea.ColumnStyles[1].Width = open ? 42 : 0;
            if (!open) return;
            row = rows[selectedId]; row.SetSelected(true);
            detailText.SuspendLayout();
            try {
                foreach (Control item in detailText.Items.Cast<Control>().ToArray()) item.Dispose();
                AddDetails(row.Mod.title, Theme.DetailTitle, Theme.Paper, 14);
                if (row.InCatalog) AddDetails("Версия в каталоге   " + row.Mod.version, Theme.Small, Theme.Muted, 6);
                if (row.Installed != null) AddDetails("Установленная версия   " + row.Installed.version, Theme.Small, Theme.Muted, 6);
                string author = row.Mod.author;
                if (String.IsNullOrWhiteSpace(author) && row.Installed != null && gameFolder != null) author = gameFolder.InstalledAuthor(row.Installed);
                AddDetails("Автор   " + (String.IsNullOrWhiteSpace(author) ? "не указан" : author), Theme.Small, Theme.Muted, 15);
                if (row.Mod.dependencies.Length > 0) {
                    AddDetails("Зависимости   " + String.Join(", ", row.Mod.dependencies.Select(d => rows.ContainsKey(d) ? rows[d].Mod.title : d)), Theme.Small, Theme.Muted, 10);
                }
                string description = String.IsNullOrWhiteSpace(row.Mod.description) ? "Описание пока не добавлено." : row.Mod.description.Trim();
                AddDetails(description, Theme.Body, Theme.Text, 12);
                if (!String.IsNullOrWhiteSpace(row.Mod.details)) AddDetails(row.Mod.details.Trim(), Theme.Body, Theme.Text, 8);
            } finally { detailText.ResumeLayout(); detailText.Arrange(); detailText.Offset = 0; }
        }

        void AddDetails(string text, Font font, Color color, int spaceAfter) {
            var label = Theme.Label(text, font, color);
            label.AutoEllipsis = false; label.TextAlign = ContentAlignment.TopLeft;
            label.Margin = new Padding(0, 0, 0, spaceAfter);
            detailText.Items.Add(label);
        }

        protected override bool ProcessCmdKey(ref Message message, Keys keyData) {
            if (keyData == Keys.Escape && selectedId != null) { SelectMod(null); return true; }
            return base.ProcessCmdKey(ref message, keyData);
        }

        public bool PreFilterMessage(ref Message message) {
            const int mouseWheel = 0x020a;
            if (message.Msg != mouseWheel || !Visible) return false;
            long position = message.LParam.ToInt64();
            var cursor = new Point(unchecked((short)position), unchecked((short)(position >> 16)));
            foreach (var column in new[] { detailText, cards }) {
                if (!column.Visible || !column.RectangleToScreen(column.ClientRectangle).Contains(cursor)) continue;
                column.Wheel(unchecked((short)(message.WParam.ToInt64() >> 16)));
                return true;
            }
            return false;
        }

        async Task RunMods(IEnumerable<string> selection, bool deleting) {
            if (busy || source == null) return;
            var ids = selection.ToArray();
            if (ids.Length == 0) return;
            Installer manager;
            try { manager = new Installer(pathBox.Text); }
            catch (Exception error) { ShowError(error); return; }
            var affected = new Dictionary<string,string>();
            var committed = new HashSet<string>();
            Action<ModProgress> showProgress = update => {
                ModRow row;
                if (!rows.TryGetValue(update.Id, out row)) return;
                if (!affected.ContainsKey(update.Id)) affected.Add(update.Id, row.Installed == null ? null : row.Installed.version);
                if (update.Stage == ModStage.Complete) committed.Add(update.Id);
                int height = row.Height;
                row.SetProgress(update, !deleting);
                if (row.Height != height) cards.Arrange();
            };
            foreach (string id in ids) showProgress(new ModProgress(id, ModStage.Queued));
            IProgress<ModProgress> progress = new Progress<ModProgress>(update => { if (busy) showProgress(update); });
            ShowStatus(deleting ? "Удаление выбранных модов…" : "Обработка выбранных модов…", Theme.Muted);
            var selectedSource = source;
            bool ok = await Job(token => manager.Apply(selectedSource, deleting ? new string[0] : ids,
                deleting ? ids : new string[0], progress.Report, token));
            if (ok || committed.Count > 0) {
                if (!RenderList()) return;
            }
            foreach (var item in affected) {
                ModRow row;
                if (!rows.TryGetValue(item.Key, out row)) continue;
                if (!ok && !committed.Contains(item.Key)) { row.SetResult("Операция не завершена", Theme.Error); continue; }
                row.Checked = false;
                string message = deleting ? "Удалён" : item.Value != null && Versions.Parse(item.Value) < Versions.Parse(row.Mod.version)
                    ? "Обновлён до " + row.Mod.version : "Установлен · " + row.Mod.version;
                row.SetResult(message, Theme.Mint);
            }
            cards.Arrange();
            if (ok) ShowStatus(deleting ? "Выбранные моды удалены." : "Готово. Выбранные изменения применены, можно запускать игру.", Theme.Mint);
        }
    }
}
