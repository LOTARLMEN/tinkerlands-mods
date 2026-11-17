using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;

namespace TinkerlandsMods {
    public class CatalogResult { public Catalog catalog; public string local_root; public string json; public string notice; }
    public static class Downloads {
        public const string Repository = "LOTARLMEN/tinkerlands-mods";
        public const string RepoUrl = "https://github.com/" + Repository;
        public static byte[] Read(string source, string localRoot, long limit, Action<long,long> progress, CancellationToken cancel) {
            if (!String.IsNullOrEmpty(localRoot) && !Uri.IsWellFormedUriString(source, UriKind.Absolute)) {
                string file = SafePath.Inside(localRoot, source);
                if (new FileInfo(file).Length > limit) throw new InvalidDataException("Слишком большой файл.");
                cancel.ThrowIfCancellationRequested(); return File.ReadAllBytes(file);
            }
            Uri uri;
            if (!Uri.TryCreate(source, UriKind.Absolute, out uri) || uri.Scheme != "https" || uri.Host != "github.com" ||
                !uri.AbsolutePath.StartsWith("/" + Repository + "/releases/download/", StringComparison.Ordinal))
                throw new InvalidDataException("Загрузка разрешена только из Releases проекта: " + source);
            return Http(uri, limit, progress, cancel);
        }
        static byte[] Http(Uri uri, long limit, Action<long,long> progress, CancellationToken cancel) {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            var request = (HttpWebRequest)WebRequest.Create(uri);
            request.UserAgent = "TinkerlandsModsInstaller/" + Program.Version;
            request.Accept = "application/vnd.github+json";
            request.Timeout = 30000; request.ReadWriteTimeout = 30000;
            using (cancel.Register(() => request.Abort()))
            using (var response = (HttpWebResponse)request.GetResponse()) {
                long size = response.ContentLength;
                if (size > limit) throw new InvalidDataException("Размер загрузки превышает ограничение.");
                using (var input = response.GetResponseStream()) using (var output = new MemoryStream()) {
                    byte[] buffer = new byte[65536]; int n;
                    while ((n = input.Read(buffer, 0, buffer.Length)) > 0) {
                        cancel.ThrowIfCancellationRequested();
                        if (output.Length + n > limit) throw new InvalidDataException("Размер загрузки превышает ограничение.");
                        output.Write(buffer, 0, n); if (progress != null) progress(output.Length, size);
                    }
                    if (size >= 0 && output.Length != size) throw new IOException("Загрузка оборвалась.");
                    return output.ToArray();
                }
            }
        }
        public static CatalogResult Latest(string localCatalog, Action<long,long> progress, CancellationToken cancel) {
            if (!String.IsNullOrEmpty(localCatalog)) {
                string file = Path.GetFullPath(localCatalog);
                string localText = File.ReadAllText(file, Encoding.UTF8);
                var local = Json.Read<Catalog>(localText); Validate(local);
                return new CatalogResult { catalog = local, local_root = Path.GetDirectoryName(file), json = localText };
            }
            string releaseJson = Encoding.UTF8.GetString(Http(new Uri("https://api.github.com/repos/" + Repository + "/releases/latest"), 4 * 1024 * 1024, null, cancel));
            var release = Json.Read<Dictionary<string,object>>(releaseJson);
            var assets = (IEnumerable)release["assets"];
            Dictionary<string,object> catalogAsset = null;
            foreach (Dictionary<string,object> asset in assets)
                if (Convert.ToString(asset["name"]) == "catalog.json") catalogAsset = asset;
            if (catalogAsset == null) throw new InvalidDataException("В последнем релизе нет catalog.json.");
            byte[] bytes = Read(Convert.ToString(catalogAsset["browser_download_url"]), null, 4 * 1024 * 1024, progress, cancel);
            object digest;
            if (catalogAsset.TryGetValue("digest", out digest) && digest != null && Convert.ToString(digest).StartsWith("sha256:"))
                Verify(bytes, Convert.ToString(digest).Substring(7));
            string text = Encoding.UTF8.GetString(bytes);
            var catalog = Json.Read<Catalog>(text); Validate(catalog);
            return new CatalogResult { catalog = catalog, json = text };
        }
        public static void Verify(byte[] bytes, string sha) {
            if (!Hash.Valid(sha) || Hash.Bytes(bytes) != sha) throw new InvalidDataException("Контрольная сумма файла не совпадает. Установка отменена.");
        }
        public static void Validate(Catalog catalog) {
            if (catalog == null || catalog.schema != 1 || catalog.mods == null || catalog.mods.Count > 100)
                throw new InvalidDataException("Неподдерживаемый каталог модов.");
            var ids = new HashSet<string>(); var allPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var mod in catalog.mods) {
                if (mod == null || !SafePath.Id(mod.id) || !ids.Add(mod.id) || String.IsNullOrWhiteSpace(mod.title) ||
                    String.IsNullOrWhiteSpace(mod.url) || !Hash.Valid(mod.sha256) || mod.files == null || mod.files.Count == 0 || mod.files.Count > 1000)
                    throw new InvalidDataException("Неверная запись мода.");
                Versions.Parse(mod.version);
                foreach (var file in mod.files) {
                    if (file == null || !Hash.Valid(file.sha256)) throw new InvalidDataException("Нет хеша файла мода.");
                    SafePath.Payload(file.path, mod.id);
                    if (!allPaths.Add(file.path)) throw new InvalidDataException("Два мода используют один файл: " + file.path);
                }
                if (mod.game_sha256 == null || mod.game_sha256.Any(h => !Hash.Valid(h))) throw new InvalidDataException("Неверный хеш версии игры.");
                if (mod.dependencies == null || mod.dependencies.Any(d => !SafePath.Id(d))) throw new InvalidDataException("Неверные зависимости.");
            }
            foreach (var mod in catalog.mods) foreach (string dependency in mod.dependencies)
                if (dependency == mod.id || !ids.Contains(dependency)) throw new InvalidDataException("Неизвестная зависимость: " + dependency);
            if (catalog.installer != null) {
                Versions.Parse(catalog.installer.version);
                if (!Hash.Valid(catalog.installer.sha256) || String.IsNullOrEmpty(catalog.installer.url)) throw new InvalidDataException("Неверное обновление установщика.");
            }
        }
    }
}
