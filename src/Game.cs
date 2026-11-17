using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace TinkerlandsMods {
    public static class Game {
        public const string AppId = "2617700";
        public static void Validate(string root) {
            if (String.IsNullOrWhiteSpace(root)) throw new IOException("Укажите папку Tinkerlands.");
            root = Path.GetFullPath(root);
            // Check the entire ancestor chain before creating any installer files.
            for (var p = new DirectoryInfo(root); p != null; p = p.Parent) SafePath.CheckReparse(p.FullName);
            string exe = SafePath.Inside(root, "tinkerlands.exe");
            if (!File.Exists(exe) || !File.Exists(SafePath.Inside(root, "data.win"))) throw new IOException("В папке нет tinkerlands.exe и data.win.");
            using (var f = File.OpenRead(exe)) using (var r = new BinaryReader(f)) {
                if (f.Length < 128 || r.ReadUInt16() != 0x5a4d) throw new IOException("Неверный EXE игры.");
                f.Position = 0x3c; int pe = r.ReadInt32();
                if (pe < 64 || pe > f.Length - 6) throw new IOException("Неверный PE игры.");
                f.Position = pe;
                if (r.ReadUInt32() != 0x4550 || r.ReadUInt16() != 0x8664) throw new IOException("Нужна 64-битная Tinkerlands.");
            }
        }
        public static bool Running() {
            var processes = Process.GetProcessesByName("tinkerlands");
            try { return processes.Length != 0; } finally { foreach (var p in processes) p.Dispose(); }
        }
        public static IEnumerable<string> Values(string text, string key) {
            foreach (Match m in Regex.Matches(text, "\"" + Regex.Escape(key) + "\"\\s*\"((?:\\\\.|[^\"\\\\])*)\""))
                yield return m.Groups[1].Value.Replace("\\\\", "\\").Replace("\\\"", "\"");
        }
        static string Reg(string key, string name) {
            try { return Convert.ToString(Registry.GetValue(key, name, "")); } catch { return ""; }
        }
        static string Read(string file) { return File.Exists(file) ? File.ReadAllText(file) : ""; }
        public static List<string> Discover() {
            var found = new List<string>();
            Action<string> candidate = path => {
                if (String.IsNullOrEmpty(path)) return;
                try { Validate(path); path = Path.GetFullPath(path); if (!found.Contains(path, StringComparer.OrdinalIgnoreCase)) found.Add(path); }
                catch (IOException) {} catch (UnauthorizedAccessException) {} catch (ArgumentException) {}
            };
            var own = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            for (int i = 0; i < 4 && own != null; i++, own = own.Parent) candidate(own.FullName);
            candidate(Reg("HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " + AppId, "InstallLocation"));
            var steamRoots = new[] { Reg("HKEY_CURRENT_USER\\Software\\Valve\\Steam", "SteamPath"),
                Reg("HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath") };
            foreach (string steam in steamRoots.Where(p => !String.IsNullOrEmpty(p))) {
                var libraries = new List<string> { steam };
                libraries.AddRange(Values(Read(Path.Combine(steam, "steamapps", "libraryfolders.vdf")), "path"));
                foreach (string library in libraries.Distinct(StringComparer.OrdinalIgnoreCase)) {
                    string apps = Path.Combine(library, "steamapps");
                    foreach (string dir in Values(Read(Path.Combine(apps, "appmanifest_" + AppId + ".acf")), "installdir")) {
                        if (dir.IndexOfAny(new[] { '/', '\\', ':' }) >= 0 || dir == "..") continue;
                        candidate(Path.Combine(apps, "common", dir));
                    }
                }
            }
            return found;
        }
    }
}
