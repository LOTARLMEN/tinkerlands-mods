using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace TinkerlandsMods {
    public class PayloadFile { public string path; public string sha256; }
    public class Mod {
        public string id, title, version, description, url, sha256;
        public string[] dependencies = new string[0];
        public string[] game_sha256 = new string[0];
        public List<PayloadFile> files = new List<PayloadFile>();
    }
    public class InstallerRelease { public string version, url, sha256; }
    public class Catalog {
        public int schema;
        public string release;
        public InstallerRelease installer;
        public List<Mod> mods = new List<Mod>();
    }
    public class InstalledMod {
        public string id, version;
        public string[] dependencies = new string[0];
        public List<PayloadFile> files = new List<PayloadFile>();
    }
    public class InstalledState {
        public int schema = 1;
        public List<InstalledMod> mods = new List<InstalledMod>();
    }
    public class UndoFile {
        public string path, old_hash, new_hash, backup;
        public bool existed;
    }
    public class Journal {
        public int schema = 1;
        public string phase = "prepared", state_before;
        public List<UndoFile> files = new List<UndoFile>();
    }
    public static class Json {
        public static T Read<T>(string text) {
            var json = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024, RecursionLimit = 64 };
            return json.Deserialize<T>(text);
        }
        public static string Write(object value) { return new JavaScriptSerializer().Serialize(value); }
    }
    public static class Hash {
        public static string Bytes(byte[] bytes) {
            using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
        }
        public static string File(string path) {
            using (var f = System.IO.File.OpenRead(path))
            using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(f)).Replace("-", "").ToLowerInvariant();
        }
        public static bool Valid(string value) { return value != null && Regex.IsMatch(value, "^[a-f0-9]{64}$"); }
    }
    public static class SafePath {
        static readonly Regex IdPattern = new Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$");
        static readonly Regex Device = new Regex("^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\\.|$)", RegexOptions.IgnoreCase);
        public static bool Id(string value) { return value != null && value.Length <= 64 && IdPattern.IsMatch(value); }
        public static string Relative(string value) {
            if (String.IsNullOrEmpty(value) || value.Length > 220 || value.Contains("\\") || value.StartsWith("/") || value.Contains(":"))
                throw new InvalidDataException("Недопустимый путь: " + value);
            foreach (string part in value.Split('/')) {
                if (part == "" || part == "." || part == ".." || part.EndsWith(".") || part.EndsWith(" ") || Device.IsMatch(part) || part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                    throw new InvalidDataException("Недопустимая часть пути: " + value);
            }
            return value;
        }
        public static string Payload(string value, string id) {
            Relative(value);
            var pieces = value.Split('/');
            bool adapter = pieces.Length == 2 && pieces[0] == "mods" && pieces[1].EndsWith(".mod", StringComparison.OrdinalIgnoreCase);
            bool library = pieces.Length == 4 && pieces[0] == "mods" && pieces[1] == "native" && pieces[2] == id && pieces[3].EndsWith(".dll", StringComparison.OrdinalIgnoreCase);
            if (!adapter && !library) throw new InvalidDataException("Файл вне каталога модов: " + value);
            return value;
        }
        public static string Inside(string root, string relative) {
            Relative(relative);
            root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
            string result = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!result.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Выход за пределы папки");
            CheckReparse(root);
            string at = root;
            foreach (string part in relative.Split('/')) { at = Path.Combine(at, part); CheckReparse(at); }
            return result;
        }
        public static void CheckReparse(string path) {
            // GetAttributes also detects a dangling symlink, unlike File.Exists.
            try {
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Ссылка/reparse point запрещена: " + path);
            } catch (FileNotFoundException) {} catch (DirectoryNotFoundException) {}
        }
    }
    public static class Versions {
        public static Version Parse(string text) {
            Version v;
            if (text == null || !Regex.IsMatch(text, "^[0-9]+\\.[0-9]+\\.[0-9]+(?:\\.[0-9]+)?$") || !Version.TryParse(text, out v))
                throw new InvalidDataException("Неверная версия: " + text);
            return new Version(v.Major, v.Minor, Math.Max(0, v.Build), Math.Max(0, v.Revision));
        }
    }
}
