using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading;

namespace TinkerlandsMods {
    static class Tests {
        static int passed, failed;
        static void Assert(bool value, string message) { if (!value) throw new Exception(message); }
        static void Throws(Action action) { bool thrown = false; try { action(); } catch { thrown = true; } Assert(thrown, "Ожидался отказ"); }
        static void Check(string name, Action action) {
            try { action(); passed++; Console.WriteLine("PASS " + name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL " + name + ": " + e); }
        }
        static byte[] Archive(Dictionary<string,byte[]> files) {
            using (var memory = new MemoryStream()) {
                using (var zip = new ZipArchive(memory, ZipArchiveMode.Create, true)) foreach (var pair in files) {
                    using (var stream = zip.CreateEntry(pair.Key).Open()) stream.Write(pair.Value, 0, pair.Value.Length);
                }
                return memory.ToArray();
            }
        }
        static byte[] ModFile(int id, string content) {
            return Archive(new Dictionary<string,byte[]> {
                {"info.json", Encoding.UTF8.GetBytes(Json.Write(new { name = "test", version = "1.0.0" }))},
                {"scripts/test.json", Encoding.UTF8.GetBytes(Json.Write(new { id = id, key = "test", code = content }))}
            });
        }
        sealed class Fixture : IDisposable {
            public string Root = Path.Combine(Path.GetTempPath(), "TinkerlandsInstallerTest-" + Guid.NewGuid().ToString("N"));
            public string GameRoot, Packages;
            public bool Running;
            public Fixture() {
                GameRoot = Path.Combine(Root, "Игра с пробелом"); Packages = Path.Combine(Root, "packages");
                Directory.CreateDirectory(GameRoot); Directory.CreateDirectory(Packages);
                byte[] pe = new byte[512]; pe[0] = 0x4d; pe[1] = 0x5a; pe[0x3c] = 0x80; pe[0x80] = 0x50; pe[0x81] = 0x45; pe[0x84] = 0x64; pe[0x85] = 0x86;
                File.WriteAllBytes(Path.Combine(GameRoot, "tinkerlands.exe"), pe); File.WriteAllText(Path.Combine(GameRoot, "data.win"), "untouched");
            }
            public Mod Package(string id, string version, string contents, bool dll) {
                var files = new Dictionary<string,byte[]> { {"mods/" + id + ".mod", ModFile(id == "sample" ? 16080 : 16081, contents)} };
                if (dll) files.Add("mods/native/" + id + "/runtime.dll", Encoding.UTF8.GetBytes(contents + " DLL"));
                string name = id + "-" + version + ".zip"; byte[] archive = Archive(files); File.WriteAllBytes(Path.Combine(Packages, name), archive);
                return new Mod { id = id, title = id, version = version, description = contents, url = name, sha256 = Hash.Bytes(archive),
                    files = files.Select(p => new PayloadFile { path = p.Key, sha256 = Hash.Bytes(p.Value) }).ToList() };
            }
            public CatalogResult Source(params Mod[] mods) { return new CatalogResult { catalog = new Catalog { schema = 1, release = "test", mods = mods.ToList() }, local_root = Packages }; }
            public Installer Manager() { return new Installer(GameRoot, () => Running); }
            public string PathOf(string relative) { return SafePath.Inside(GameRoot, relative); }
            public void Apply(CatalogResult source, string install, string remove) { Manager().Apply(source, install == null ? new string[0] : new[] { install }, remove == null ? new string[0] : new[] { remove }, null, CancellationToken.None); }
            public void Dispose() {
                // The root is a literal, generated test directory under the OS temp directory.
                string full = Path.GetFullPath(Root), temp = Path.GetFullPath(Path.GetTempPath());
                if (!full.StartsWith(temp, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(full).StartsWith("TinkerlandsInstallerTest-")) throw new Exception("Unsafe test cleanup");
                Directory.Delete(full, true);
            }
        }
        public static int Run() {
            Check("install-update-remove / native DLL directory / immutable game files", () => {
                using (var f = new Fixture()) {
                    string gameHash = Hash.File(f.PathOf("tinkerlands.exe")); var v1 = f.Package("sample", "1.0.0", "one", true); f.Apply(f.Source(v1), "sample", null);
                    Assert(File.Exists(f.PathOf("mods/native/sample/runtime.dll")), "DLL missing");
                    Assert(!File.Exists(f.PathOf("runtime.dll")), "Root DLL pollution");
                    var v2 = f.Package("sample", "1.1.0", "two", true); Assert(f.Manager().Status(v2, f.Manager().ReadState()) == "Есть обновление", "Update not detected");
                    f.Apply(f.Source(v2), "sample", null); Assert(f.Manager().ReadState().mods.Single().version == "1.1.0", "Wrong installed version");
                    File.WriteAllText(f.PathOf("mods/native/sample/user.ini"), "keep settings");
                    f.Apply(f.Source(), null, "sample");
                    Assert(!File.Exists(f.PathOf("mods/sample.mod")) && !File.Exists(f.PathOf("mods/native/sample/runtime.dll")), "Owned files remain");
                    Assert(File.Exists(f.PathOf("mods/native/sample/user.ini")), "Unknown file was removed");
                    Assert(Hash.File(f.PathOf("tinkerlands.exe")) == gameHash && File.ReadAllText(f.PathOf("data.win")) == "untouched", "Game changed");
                }
            });
            Check("checksum mismatch writes no payload", () => {
                using (var f = new Fixture()) { var mod = f.Package("sample", "1.0.0", "one", false); mod.sha256 = new string('0', 64); Throws(() => f.Apply(f.Source(mod), "sample", null)); Assert(!File.Exists(f.PathOf("mods/sample.mod")), "Payload was written"); }
            });
            Check("foreign and changed files are preserved", () => {
                using (var f = new Fixture()) {
                    var mod = f.Package("sample", "1.0.0", "one", false); Directory.CreateDirectory(f.PathOf("mods")); File.WriteAllText(f.PathOf("mods/sample.mod"), "foreign");
                    Throws(() => f.Apply(f.Source(mod), "sample", null)); Assert(File.ReadAllText(f.PathOf("mods/sample.mod")) == "foreign", "Foreign file changed");
                    File.Delete(f.PathOf("mods/sample.mod")); f.Apply(f.Source(mod), "sample", null); File.WriteAllText(f.PathOf("mods/sample.mod"), "modified");
                    Throws(() => f.Apply(f.Source(mod), "sample", null)); Throws(() => f.Apply(f.Source(), null, "sample")); Assert(File.ReadAllText(f.PathOf("mods/sample.mod")) == "modified", "Modified file changed");
                }
            });
            Check("transaction failure restores both files and state", () => {
                using (var f = new Fixture()) {
                    var first = f.Package("sample", "1.0.0", "one", true); f.Apply(f.Source(first), "sample", null);
                    string beforeMod = Hash.File(f.PathOf("mods/sample.mod")), beforeDll = Hash.File(f.PathOf("mods/native/sample/runtime.dll")), beforeState = File.ReadAllText(f.PathOf(".tinkerlands-mods/installed.json"));
                    var next = f.Package("sample", "2.0.0", "two", true); var manager = f.Manager(); int writes = 0;
                    manager.BeforeWrite = path => { if (++writes == 2) throw new IOException("injected write failure"); };
                    Throws(() => manager.Apply(f.Source(next), new[] { "sample" }, new string[0], null, CancellationToken.None));
                    Assert(Hash.File(f.PathOf("mods/sample.mod")) == beforeMod && Hash.File(f.PathOf("mods/native/sample/runtime.dll")) == beforeDll, "Incomplete file rollback");
                    Assert(File.ReadAllText(f.PathOf(".tinkerlands-mods/installed.json")) == beforeState, "State rollback failed");
                }
            });
            Check("interrupted transaction resumes undo after game is closed", () => {
                using (var f = new Fixture()) {
                    var mod = f.Package("sample", "1.0.0", "one", true); var manager = f.Manager(); manager.BeforeWrite = path => f.Running = true;
                    Throws(() => manager.Apply(f.Source(mod), new[] { "sample" }, new string[0], null, CancellationToken.None));
                    Assert(File.Exists(f.PathOf("mods/sample.mod")), "Interruption was not exercised");
                    Throws(() => f.Manager().Recover()); f.Running = false; f.Manager().Recover();
                    Assert(!File.Exists(f.PathOf("mods/sample.mod")) && f.Manager().ReadState().mods.Count == 0, "Interrupted transaction not restored");
                }
            });
            Check("running game rejects all mutations before metadata creation", () => {
                using (var f = new Fixture()) { var mod = f.Package("sample", "1.0.0", "one", false); f.Running = true; Throws(() => f.Apply(f.Source(mod), "sample", null)); Assert(!Directory.Exists(f.PathOf(".tinkerlands-mods")), "Metadata created while running"); }
            });
            Check("path traversal, root game files, ADS and Windows aliases rejected", () => {
                foreach (string path in new[] { "../outside", "mods/../data.win", "C:/mods/test.mod", "mods/file.mod:stream", "mods/CON.mod", "mods/file.mod.", "mods/file.mod ", "mods\\test.mod", "tinkerlands.exe", "version.dll", "mods/native/other/runtime.dll" }) Throws(() => SafePath.Payload(path, "sample"));
            });
            Check("zip extra files and case-insensitive duplicates rejected", () => {
                using (var f = new Fixture()) {
                    var mod = f.Package("sample", "1.0.0", "one", false);
                    var data = new Dictionary<string,byte[]> { {"mods/sample.mod", ModFile(16080,"one")}, {"mods/SAMPLE.mod", ModFile(16080,"one")} };
                    byte[] zip = Archive(data); mod.sha256 = Hash.Bytes(zip); Throws(() => Installer.Unpack(mod, zip));
                    data.Remove("mods/SAMPLE.mod"); data.Add("data.win", new byte[] {1}); zip = Archive(data); mod.sha256 = Hash.Bytes(zip); Throws(() => Installer.Unpack(mod, zip));
                }
            });
            Check("duplicate custom script ids rejected before writes", () => {
                using (var f = new Fixture()) {
                    var mod = f.Package("sample", "1.0.0", "one", false); Directory.CreateDirectory(f.PathOf("mods")); File.WriteAllBytes(f.PathOf("mods/old-name.mod"), ModFile(16080,"old"));
                    Throws(() => f.Apply(f.Source(mod), "sample", null)); Assert(!File.Exists(f.PathOf("mods/sample.mod")), "Conflicting mod installed");
                }
            });
            Check("archive symlinks rejected", () => {
                using (var f = new Fixture()) {
                    var mod=f.Package("sample","1.0.0","one",false); byte[] bytes;
                    using(var memory=new MemoryStream()) {
                        using(var zip=new ZipArchive(memory,ZipArchiveMode.Create,true)) {
                            var entry=zip.CreateEntry("mods/sample.mod");entry.ExternalAttributes=unchecked((int)0xa1ff0000);
                            byte[] body=ModFile(16080,"one");using(var stream=entry.Open())stream.Write(body,0,body.Length);
                        }
                        bytes=memory.ToArray();
                    }
                    mod.sha256=Hash.Bytes(bytes);Throws(()=>Installer.Unpack(mod,bytes));
                }
            });
            Check("existing directory junction cannot redirect installation", () => {
                using(var f=new Fixture()) {
                    string link=Path.Combine(f.GameRoot,"mods"),outside=Path.Combine(f.Root,"outside");Directory.CreateDirectory(outside);
                    File.WriteAllText(Path.Combine(outside,"keep.txt"),"untouched");
                    if(link.Contains("\"") || outside.Contains("\""))throw new Exception("Unexpected test path quote");
                    using(var p=Process.Start(new ProcessStartInfo("cmd.exe","/d /c mklink /J \""+link+"\" \""+outside+"\"") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true})) {
                        p.StandardOutput.ReadToEnd();string error=p.StandardError.ReadToEnd();p.WaitForExit();Assert(p.ExitCode==0,"Junction setup failed: "+error);
                    }
                    try {Throws(()=>SafePath.Inside(f.GameRoot,"mods/sample.mod"));}
                    finally { Directory.Delete(link); } // nonrecursive: remove only the junction itself
                    Assert(File.ReadAllText(Path.Combine(outside,"keep.txt"))=="untouched","Junction target changed");
                }
            });
            Check("two installers cannot hold the same game mutation lock", () => {
                using(var f=new Fixture()) {
                    Directory.CreateDirectory(f.PathOf(".tinkerlands-mods"));
                    using(var held=new FileStream(f.PathOf(".tinkerlands-mods/operation.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)) {
                        var mod=f.Package("sample","1.0.0","one",false);Throws(()=>f.Apply(f.Source(mod),"sample",null));
                        Assert(!File.Exists(f.PathOf("mods/sample.mod")),"Concurrent writer changed payload");
                    }
                }
            });
            Check("dependencies install together and survive offline removal checks", () => {
                using (var f = new Fixture()) {
                    var a = f.Package("sample", "1.0.0", "a", false); var b = f.Package("helper", "1.0.0", "b", false); a.dependencies = new[] {"helper"};
                    f.Apply(f.Source(a,b), "sample", null); Assert(f.Manager().ReadState().mods.Count == 2, "Dependency missing");
                    Throws(() => f.Apply(f.Source(), null, "helper")); Assert(File.Exists(f.PathOf("mods/helper.mod")), "Required dependency removed offline");
                }
            });
            Check("numeric versions and Steam library paths", () => {
                Assert(Versions.Parse("1.10.0") > Versions.Parse("1.9.9"), "Lexical version comparison");
                string vdf = "\"libraryfolders\" { \"0\" { \"path\" \"D:\\\\SteamLibrary\" } \"1\" { \"path\" \"E:\\\\Игры Steam\" } }";
                Assert(Game.Values(vdf,"path").SequenceEqual(new[] {"D:\\SteamLibrary", "E:\\Игры Steam"}), "Steam VDF paths invalid");
            });
            Check("dependency cycle and shared payload ownership rejected", () => {
                using (var f = new Fixture()) {
                    var a = f.Package("sample", "1.0.0", "a", false); var b = f.Package("helper", "1.0.0", "b", false); a.dependencies = new[] {"helper"}; b.dependencies = new[] {"sample"};
                    Throws(() => f.Apply(f.Source(a,b), "sample", null)); b.dependencies = new string[0]; a.dependencies = new string[0]; b.files[0].path = a.files[0].path;
                    Throws(() => Downloads.Validate(f.Source(a,b).catalog));
                }
            });
            Check("self-update verifies version/hash and rolls back failed start", () => {
                using (var f = new Fixture()) {
                    string self = Process.GetCurrentProcess().MainModule.FileName; byte[] next = File.ReadAllBytes(self);
                    string target = Path.Combine(f.Root, "TinkerlandsModsInstaller.exe"); File.WriteAllText(target,"previous installer");
                    var release = new InstallerRelease {version = Program.Version, sha256 = Hash.Bytes(next)};
                    Throws(() => SelfUpdate.Swap(target,next,release,path => {throw new IOException("injected start failure");}));
                    Assert(File.ReadAllText(target) == "previous installer", "Updater did not restore previous EXE");
                    bool started = false; SelfUpdate.Swap(target,next,release,path => {started = Hash.File(path) == release.sha256;}); Assert(started,"New EXE not started");
                    SelfUpdate.Confirm(target); Assert(!File.Exists(target + ".previous.exe"), "Confirmed backup not cleaned");
                    SelfUpdate.Swap(target,next,release,path => {started = true;}); SelfUpdate.Confirm(target);
                    Assert(SelfUpdate.Available(new InstallerRelease {version="0.2.0"}), "Update not offered");
                    Assert(!SelfUpdate.Available(new InstallerRelease {version=Program.Version}), "Same version offered");
                }
            });
            Check("self-update replacement can execute CLI in its new location", () => {
                using (var f = new Fixture()) {
                    string self = Process.GetCurrentProcess().MainModule.FileName; byte[] next = File.ReadAllBytes(self);
                    string target = Path.Combine(f.Root,"TinkerlandsModsInstaller.exe"); File.WriteAllText(target,"old");
                    var release = new InstallerRelease {version=Program.Version,sha256=Hash.Bytes(next)};
                    SelfUpdate.Swap(target,next,release,path => {
                        using (var process = Process.Start(new ProcessStartInfo(path,"--version") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true})) {
                            string output=process.StandardOutput.ReadToEnd(); process.WaitForExit(); Assert(process.ExitCode==0 && output.Trim()==Program.Version,"Updated EXE failed to start");
                        }
                    });
                    SelfUpdate.Confirm(target);
                }
            });
            Console.WriteLine("Tests: " + passed + " passed, " + failed + " failed"); return failed == 0 ? 0 : 1;
        }
    }
}
