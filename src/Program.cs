using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace TinkerlandsMods {
    static class Program {
        public const string Version = "0.1.1";
        public static readonly string UserFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TinkerlandsMods");
        public static string LogPath { get { return Path.Combine(UserFolder, "installer.log"); } }
        public static void Log(string text) {
            try { Directory.CreateDirectory(UserFolder); File.AppendAllText(LogPath, DateTime.UtcNow.ToString("o") + " " + text + Environment.NewLine, Encoding.UTF8); }
            catch (IOException) {} catch (UnauthorizedAccessException) {}
        }
        public static string InitialGame() {
            string config = Path.Combine(UserFolder, "game-path.txt");
            if (File.Exists(config)) {
                string path = File.ReadAllText(config).Trim();
                try { Game.Validate(path); return path; } catch (IOException) {} catch (UnauthorizedAccessException) {}
            }
            return Game.Discover().FirstOrDefault() ?? "";
        }
        [STAThread]
        static int Main(string[] args) {
            try {
                // A WinExe may have redirected pipes without an attached console.
                // SetOutputEncoding calls SetConsoleOutputCP and fails in that case.
                Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true });
                Console.SetError(new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true });
                var options = new Dictionary<string,string>();
                for (int i = 0; i < args.Length; i++) {
                    string key = args[i];
                    if (new[] { "--game", "--catalog", "--install", "--remove", "--screenshot" }.Contains(key)) {
                        if (++i >= args.Length) throw new ArgumentException("Не хватает значения: " + key);
                        options.Add(key, args[i]);
                    } else if (new[] { "--version", "--self-test", "--list", "--recover" }.Contains(key)) options.Add(key, "true");
                    else throw new ArgumentException("Неизвестный аргумент: " + key);
                }
                if (options.ContainsKey("--version")) { Console.WriteLine(Version); return 0; }
                if (options.ContainsKey("--self-test")) return Tests.Run();
                string root = options.ContainsKey("--game") ? Path.GetFullPath(options["--game"]) : InitialGame();
                string catalogPath = options.ContainsKey("--catalog") ? options["--catalog"] : null;
                bool cli = new[] { "--list", "--install", "--remove", "--recover" }.Any(options.ContainsKey);
                if (cli) {
                    var manager = new Installer(root);
                    if (options.ContainsKey("--recover")) { manager.Recover(); Console.WriteLine("Восстановление завершено."); return 0; }
                    var source = options.ContainsKey("--remove") && !options.ContainsKey("--install") ?
                        new CatalogResult { catalog = new Catalog { schema = 1, release = "offline" } } : GetCatalog(catalogPath, null, CancellationToken.None);
                    if (options.ContainsKey("--install") || options.ContainsKey("--remove")) {
                        string[] install = options.ContainsKey("--install") ? options["--install"].Split(',') : new string[0];
                        string[] remove = options.ContainsKey("--remove") ? options["--remove"].Split(',') : new string[0];
                        manager.Apply(source, install, remove, null, CancellationToken.None);
                    }
                    var state = manager.ReadState();
                    Console.WriteLine(Json.Write(new { game = root, release = source.catalog.release,
                        mods = source.catalog.mods.Select(m => new { id = m.id, title = m.title, version = m.version, status = manager.Status(m, state) }).ToArray(), managed = state.mods }));
                    return 0;
                }
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(root, catalogPath, options.ContainsKey("--screenshot") ? options["--screenshot"] : null));
                return 0;
            } catch (Exception e) {
                Log(e.ToString()); Console.Error.WriteLine(e.Message);
                if (args.Length == 0) MessageBox.Show(e.Message, "Tinkerlands Mods", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
        public static CatalogResult GetCatalog(string localPath, Action<long,long> progress, CancellationToken cancel) {
            string cache = Path.Combine(UserFolder, "catalog-cache.json");
            try {
                var result = Downloads.Latest(localPath, progress, cancel);
                if (localPath == null) { Directory.CreateDirectory(UserFolder); File.WriteAllText(cache, result.json, Encoding.UTF8); }
                return result;
            } catch (WebException error) {
                cancel.ThrowIfCancellationRequested(); if (localPath != null) throw;
                Log("GitHub unavailable: " + error.Message);
                if (File.Exists(cache)) {
                    string text = File.ReadAllText(cache, Encoding.UTF8); var catalog = Json.Read<Catalog>(text); Downloads.Validate(catalog);
                    return new CatalogResult { catalog = catalog, json = text, notice = "GitHub недоступен. Показан сохранённый каталог." };
                }
                return new CatalogResult { catalog = new Catalog { schema = 1, release = "Офлайн" }, notice = "GitHub недоступен. Установленные моды можно удалить." };
            }
        }
    }
}
