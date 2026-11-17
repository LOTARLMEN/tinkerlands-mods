using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace TinkerlandsMods {
    public static class SelfUpdate {
        public sealed class Receipt { public string current_hash, previous_hash; }
        public static void Confirm(string current) {
            string receipt = current + ".update.json", previous = current + ".previous.exe";
            SafePath.CheckReparse(receipt); SafePath.CheckReparse(previous);
            if (!File.Exists(receipt)) return;
            var state = Json.Read<Receipt>(File.ReadAllText(receipt));
            if (!Hash.Valid(state.current_hash) || !Hash.Valid(state.previous_hash))
                throw new IOException("Нельзя подтвердить предыдущее самообновление.");
            string currentHash = Hash.File(current);
            // A file lock may reject the very first rename. In that case the
            // old EXE is still intact; discard only our validated pending data.
            if (currentHash == state.previous_hash && !File.Exists(previous)) {
                string pending = current + ".next.exe"; SafePath.CheckReparse(pending);
                if (File.Exists(pending)) {
                    if (Hash.File(pending) != state.current_hash) throw new IOException("Временный EXE установщика изменён.");
                    File.Delete(pending);
                }
                File.Delete(receipt); return;
            }
            if (currentHash != state.current_hash) throw new IOException("Нельзя подтвердить предыдущее самообновление.");
            if (File.Exists(previous)) {
                if (Hash.File(previous) != state.previous_hash) throw new IOException("Резервная копия установщика изменена.");
                File.Delete(previous);
            }
            File.Delete(receipt);
        }
        public static bool Available(InstallerRelease release) { return release != null && Versions.Parse(release.version) > Versions.Parse(Program.Version); }
        public static void Swap(string current, byte[] bytes, InstallerRelease release, Action<string> start) {
            Downloads.Verify(bytes, release.sha256);
            string fresh = current + ".next.exe", previous = current + ".previous.exe";
            SafePath.CheckReparse(current); SafePath.CheckReparse(fresh); SafePath.CheckReparse(previous);
            Confirm(current);
            if (File.Exists(fresh) || File.Exists(previous)) throw new IOException("Остались файлы предыдущего самообновления. Сохраните их и освободите имена .next.exe / .previous.exe.");
            using (var f = new FileStream(fresh, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { f.Write(bytes, 0, bytes.Length); f.Flush(true); }
            try {
                var version = FileVersionInfo.GetVersionInfo(fresh);
                if (Versions.Parse(version.FileVersion) != Versions.Parse(release.version) || version.OriginalFilename != "TinkerlandsModsInstaller.exe")
                    throw new InvalidDataException("Загружен другой установщик или другая версия.");
                string receipt = current + ".update.json";
                SafePath.CheckReparse(receipt);
                File.WriteAllText(receipt, Json.Write(new Receipt { current_hash = release.sha256, previous_hash = Hash.File(current) }));
                File.Move(current, previous);
                try { File.Move(fresh, current); start(current); }
                catch { if (File.Exists(current)) File.Delete(current); File.Move(previous, current); File.Delete(receipt); throw; }
            } finally { if (File.Exists(fresh)) File.Delete(fresh); }
            // Keep the previous EXE as an explicit recovery copy; never delete arbitrary siblings.
        }
        public static void Apply(InstallerRelease release, string localRoot, Action<string,int> progress, CancellationToken cancel) {
            if (!Available(release)) throw new IOException("Новой версии установщика нет.");
            byte[] bytes = Downloads.Read(release.url, localRoot, 32 * 1024 * 1024,
                (done,total) => { if (progress != null) progress("Обновление установщика", total > 0 ? (int)(done * 100 / total) : 0); }, cancel);
            cancel.ThrowIfCancellationRequested();
            string self = Process.GetCurrentProcess().MainModule.FileName;
            Swap(self, bytes, release, path => {
                var p = Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
                if (p == null) throw new IOException("Не удалось запустить новый установщик.");
                p.Dispose();
            });
        }
    }
}
