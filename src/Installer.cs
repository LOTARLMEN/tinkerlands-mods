using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading;

namespace TinkerlandsMods {
    public sealed class Installer {
        public readonly string Root;
        readonly Func<bool> running;
        public Action<string> BeforeWrite; // Internal fault injection used only by the test executable mode.
        string StatePath { get { return SafePath.Inside(Root, ".tinkerlands-mods/installed.json"); } }
        string TransactionRoot { get { return SafePath.Inside(Root, ".tinkerlands-mods/transactions"); } }
        public Installer(string root) : this(root, Game.Running) {}
        internal Installer(string root, Func<bool> runningCheck) { Root = Path.GetFullPath(root); running = runningCheck; Game.Validate(Root); }
        void Stopped() { if (running()) throw new IOException("Закройте Tinkerlands перед установкой, обновлением или удалением модов."); }
        FileStream Lock() {
            Stopped(); string path = SafePath.Inside(Root, ".tinkerlands-mods/operation.lock");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { throw new IOException("Другой установщик уже работает с этой папкой."); }
        }
        static void Atomic(string path, byte[] bytes) {
            Directory.CreateDirectory(Path.GetDirectoryName(path)); string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
            try { if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        static void Text(string path, string text) { Atomic(path, Encoding.UTF8.GetBytes(text)); }
        public InstalledState ReadState() {
            var state = File.Exists(StatePath) ? Json.Read<InstalledState>(File.ReadAllText(StatePath)) : new InstalledState();
            if (state == null || state.schema != 1 || state.mods == null) throw new InvalidDataException("Повреждён учёт установленных модов.");
            var ids = new HashSet<string>(); var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var mod in state.mods) {
                if (!SafePath.Id(mod.id) || !ids.Add(mod.id) || mod.files == null || mod.files.Count == 0) throw new InvalidDataException("Повреждён учёт мода.");
                Versions.Parse(mod.version);
                foreach (var file in mod.files) {
                    SafePath.Payload(file.path, mod.id);
                    if (!Hash.Valid(file.sha256) || !paths.Add(file.path)) throw new InvalidDataException("Повреждён учёт файлов.");
                }
            }
            return state;
        }
        public string Status(Mod mod, InstalledState state) {
            var installed = state.mods.FirstOrDefault(m => m.id == mod.id);
            if (installed != null) {
                if (installed.files.Any(f => !File.Exists(SafePath.Inside(Root, f.path)) || Hash.File(SafePath.Inside(Root, f.path)) != f.sha256)) return "Изменён / повреждён";
                return Versions.Parse(installed.version) < Versions.Parse(mod.version) ? "Есть обновление" : "Установлен";
            }
            if (mod.files.Any(f => File.Exists(SafePath.Inside(Root, f.path)))) return "Установлен вручную";
            return "Не установлен";
        }
        public static Dictionary<string,byte[]> Unpack(Mod mod, byte[] bytes) {
            Downloads.Verify(bytes, mod.sha256);
            var expected = mod.files.ToDictionary(f => f.path, f => f.sha256, StringComparer.OrdinalIgnoreCase);
            var found = new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
            long total = 0;
            using (var input = new MemoryStream(bytes)) using (var zip = new ZipArchive(input, ZipArchiveMode.Read)) {
                if (zip.Entries.Count > 1100) throw new InvalidDataException("Слишком много файлов в архиве.");
                foreach (var entry in zip.Entries) {
                    if (entry.FullName.EndsWith("/")) { SafePath.Relative(entry.FullName.TrimEnd('/')); continue; }
                    SafePath.Payload(entry.FullName, mod.id);
                    int unixType = (entry.ExternalAttributes >> 16) & 0xf000;
                    if (unixType == 0xa000 || (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Ссылка в архиве запрещена.");
                    string hash;
                    if (!expected.TryGetValue(entry.FullName, out hash) || found.ContainsKey(entry.FullName)) throw new InvalidDataException("Лишний или повторный файл в архиве: " + entry.FullName);
                    total += entry.Length;
                    if (entry.Length < 0 || entry.Length > 128 * 1024 * 1024 || total > 256 * 1024 * 1024) throw new InvalidDataException("Архив слишком большой.");
                    using (var stream = entry.Open()) using (var output = new MemoryStream()) {
                        byte[] buffer = new byte[65536]; int n;
                        while ((n = stream.Read(buffer, 0, buffer.Length)) > 0) {
                            if (output.Length + n > entry.Length) throw new InvalidDataException("Неверный размер файла архива.");
                            output.Write(buffer, 0, n);
                        }
                        if (output.Length != entry.Length) throw new InvalidDataException("Повреждённый архив.");
                        var content = output.ToArray(); Downloads.Verify(content, hash); found.Add(entry.FullName, content);
                    }
                }
            }
            if (expected.Count != found.Count) throw new InvalidDataException("В архиве отсутствуют файлы.");
            return found;
        }
        public void Apply(CatalogResult source, IEnumerable<string> installIds, IEnumerable<string> removeIds, Action<string,int> progress, CancellationToken cancel) {
            Downloads.Validate(source.catalog);
            using (Lock()) {
                RecoverLocked(); var old = ReadState();
                var next = Json.Read<InstalledState>(Json.Write(old));
                var install = new HashSet<string>(installIds); var remove = new HashSet<string>(removeIds);
                if (install.Overlaps(remove)) throw new InvalidDataException("Мод одновременно выбран для установки и удаления.");
                Action<string,HashSet<string>> dependency = null;
                dependency = (id, chain) => {
                    var mod = source.catalog.mods.FirstOrDefault(m => m.id == id);
                    if (mod == null) throw new InvalidDataException("Неизвестный мод: " + id);
                    if (!chain.Add(id)) throw new InvalidDataException("Цикл зависимостей модов.");
                    foreach (string d in mod.dependencies) { if (remove.Contains(d)) throw new InvalidDataException("Нельзя удалить необходимую зависимость: " + d); install.Add(d); dependency(d, new HashSet<string>(chain)); }
                };
                foreach (string id in install.ToArray()) dependency(id, new HashSet<string>());
                foreach (string id in remove) if (!old.mods.Any(m => m.id == id)) throw new InvalidDataException("Этот мод не находится под управлением установщика: " + id);
                var changes = new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
                foreach (string id in remove.Concat(install)) {
                    var previous = old.mods.FirstOrDefault(m => m.id == id);
                    if (previous == null) continue;
                    foreach (var f in previous.files) {
                        string path = SafePath.Inside(Root, f.path);
                        if (!File.Exists(path) || Hash.File(path) != f.sha256) throw new IOException("Файл изменён вне установщика: " + f.path);
                        changes[f.path] = null;
                    }
                    next.mods.RemoveAll(m => m.id == id);
                }
                foreach (string id in install.OrderBy(v => v)) {
                    cancel.ThrowIfCancellationRequested(); var mod = source.catalog.mods.Single(m => m.id == id);
                    if (mod.game_sha256.Length != 0 && !mod.game_sha256.Contains(Hash.File(SafePath.Inside(Root, "tinkerlands.exe"))))
                        throw new IOException("Мод «" + mod.title + "» не поддерживает эту версию игры.");
                    if (progress != null) progress("Загрузка: " + mod.title, 0);
                    var bytes = Downloads.Read(mod.url, source.local_root, 128 * 1024 * 1024,
                        (done,total) => { if (progress != null) progress("Загрузка: " + mod.title, total > 0 ? (int)(done * 100 / total) : 0); }, cancel);
                    var files = Unpack(mod, bytes);
                    foreach (var f in mod.files) {
                        string target = SafePath.Inside(Root, f.path);
                        bool owned = old.mods.Any(m => m.id == id && m.files.Any(p => String.Equals(p.path, f.path, StringComparison.OrdinalIgnoreCase)));
                        if (old.mods.Any(m => m.id != id && m.files.Any(p => String.Equals(p.path, f.path, StringComparison.OrdinalIgnoreCase)))) throw new IOException("Файл принадлежит другому установленному моду: " + f.path);
                        if (File.Exists(target) && !owned && Hash.File(target) != f.sha256) throw new IOException("В папке уже есть другой файл: " + f.path);
                        if (Directory.Exists(target)) throw new IOException("Вместо файла существует папка: " + f.path);
                        changes[f.path] = files[f.path];
                    }
                    next.mods.Add(new InstalledMod { id = id, version = mod.version, files = mod.files, dependencies = mod.dependencies });
                }
                foreach (var m in next.mods) {
                    if (m.dependencies == null || m.dependencies.Any(d => !next.mods.Any(n => n.id == d))) throw new IOException("Удаление оставляет мод без зависимости: " + m.id);
                }
                if (changes.Count == 0) return;
                CheckScriptCollisions(changes);
                cancel.ThrowIfCancellationRequested(); Stopped();
                string tx = Guid.NewGuid().ToString("N"), txRoot = SafePath.Inside(Root, ".tinkerlands-mods/transactions/" + tx);
                Directory.CreateDirectory(txRoot);
                var journal = new Journal { state_before = File.Exists(StatePath) ? File.ReadAllText(StatePath) : null };
                foreach (var change in changes) {
                    string path = SafePath.Inside(Root, change.Key); bool exists = File.Exists(path);
                    string backup = "undo/" + journal.files.Count + ".bin";
                    if (exists) { string dest = SafePath.Inside(txRoot, backup); Directory.CreateDirectory(Path.GetDirectoryName(dest)); File.Copy(path, dest); }
                    journal.files.Add(new UndoFile { path = change.Key, existed = exists, old_hash = exists ? Hash.File(path) : null,
                        new_hash = change.Value == null ? null : Hash.Bytes(change.Value), backup = backup });
                }
                string journalPath = SafePath.Inside(txRoot, "journal.json"); Text(journalPath, Json.Write(journal));
                try {
                    int n = 0;
                    foreach (var change in changes) {
                        Stopped(); string target = SafePath.Inside(Root, change.Key);
                        if (BeforeWrite != null) BeforeWrite(change.Key);
                        if (change.Value == null) File.Delete(target); else Atomic(target, change.Value);
                        if (progress != null) progress("Применение изменений", ++n * 100 / changes.Count);
                    }
                    Stopped(); Text(StatePath, Json.Write(next)); journal.phase = "committed"; Text(journalPath, Json.Write(journal));
                } catch {
                    if (!running()) Rollback(txRoot, journal); // Otherwise keep the durable journal until the game is closed.
                    throw;
                }
                // Keep undo data outside mods. Unknown files and user settings are never swept.
                PruneEmptyDirectories(changes.Keys);
            }
        }
        void CheckScriptCollisions(Dictionary<string,byte[]> changes) {
            var owners = new Dictionary<int,string>();
            Action<string,byte[]> inspect = (path,bytes) => {
                if (bytes.Length > 32 * 1024 * 1024) throw new InvalidDataException("Слишком большой .mod: " + path);
                using (var memory = new MemoryStream(bytes)) using (var zip = new ZipArchive(memory, ZipArchiveMode.Read)) {
                    if (zip.Entries.Count > 10000) throw new InvalidDataException("Слишком много записей в .mod: " + path);
                    foreach (var entry in zip.Entries.Where(e => e.FullName.StartsWith("scripts/", StringComparison.Ordinal) && e.FullName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))) {
                        if (entry.Length > 4 * 1024 * 1024) throw new InvalidDataException("Скрипт .mod слишком большой.");
                        using (var input = entry.Open()) using (var reader = new StreamReader(input, Encoding.UTF8)) {
                            var script = Json.Read<Dictionary<string,object>>(reader.ReadToEnd());
                            if (!script.ContainsKey("id")) throw new InvalidDataException("Нет id скрипта: " + path);
                            int id = Convert.ToInt32(script["id"]); string owner;
                            if (owners.TryGetValue(id, out owner)) throw new InvalidDataException("Конфликт id скрипта " + id + ": " + owner + " и " + path);
                            owners.Add(id, path);
                        }
                    }
                }
            };
            foreach (var change in changes.Where(p => p.Key.EndsWith(".mod", StringComparison.OrdinalIgnoreCase) && p.Value != null)) inspect(change.Key, change.Value);
            string mods = SafePath.Inside(Root, "mods");
            if (!Directory.Exists(mods)) return;
            foreach (string file in Directory.GetFiles(mods, "*.mod")) {
                string relative = "mods/" + Path.GetFileName(file); SafePath.Inside(Root, relative);
                if (!changes.ContainsKey(relative)) inspect(relative, File.ReadAllBytes(file));
            }
        }
        void PruneEmptyDirectories(IEnumerable<string> paths) {
            foreach (string value in paths) {
                var dir = new DirectoryInfo(Path.GetDirectoryName(SafePath.Inside(Root, value)));
                while (dir != null && dir.FullName.StartsWith(Path.Combine(Root, "mods") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) && !dir.EnumerateFileSystemInfos().Any()) {
                    SafePath.CheckReparse(dir.FullName); var parent = dir.Parent; dir.Delete(); dir = parent;
                }
            }
        }
        public void Recover() { using (Lock()) RecoverLocked(); }
        void RecoverLocked() {
            if (!Directory.Exists(TransactionRoot)) return;
            foreach (string tx in Directory.GetDirectories(TransactionRoot)) {
                SafePath.CheckReparse(tx);
                string journalPath = SafePath.Inside(tx, "journal.json");
                if (!File.Exists(journalPath)) continue;
                var journal = Json.Read<Journal>(File.ReadAllText(journalPath));
                if (journal.schema != 1 || journal.files == null) throw new InvalidDataException("Повреждён журнал установки.");
                if (journal.phase == "prepared") Rollback(tx, journal);
                else if (journal.phase != "committed" && journal.phase != "rolled_back") throw new InvalidDataException("Неверное состояние транзакции.");
            }
        }
        void Rollback(string txRoot, Journal journal) {
            Stopped();
            // Validate the entire undo before changing any files.
            foreach (var f in journal.files) {
                SafePath.Relative(f.path);
                if (!f.path.StartsWith("mods/", StringComparison.Ordinal)) throw new InvalidDataException("Неверный путь восстановления.");
                string target = SafePath.Inside(Root, f.path);
                if (File.Exists(target)) {
                    string current = Hash.File(target);
                    if (current != f.old_hash && current != f.new_hash) throw new IOException("Файл изменён после прерванной установки: " + f.path);
                }
                if (f.existed && (!Hash.Valid(f.old_hash) || Hash.File(SafePath.Inside(txRoot, f.backup)) != f.old_hash)) throw new IOException("Повреждена резервная копия.");
            }
            foreach (var f in journal.files.AsEnumerable().Reverse()) {
                Stopped(); string target = SafePath.Inside(Root, f.path);
                if (f.existed) Atomic(target, File.ReadAllBytes(SafePath.Inside(txRoot, f.backup)));
                else if (File.Exists(target)) File.Delete(target);
            }
            if (journal.state_before == null) { if (File.Exists(StatePath)) File.Delete(StatePath); }
            else Text(StatePath, journal.state_before);
            journal.phase = "rolled_back"; Text(SafePath.Inside(txRoot, "journal.json"), Json.Write(journal));
        }
    }
}
