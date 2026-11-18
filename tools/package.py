"""Reproducible release assets. Reads only this repository, never the game folder."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
def sha(data): return hashlib.sha256(data).hexdigest()
def json_bytes(value): return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
def archive(path, files):
    with zipfile.ZipFile(path, 'w') as z:
        for name, data in sorted(files.items()):
            item = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100644 << 16
            z.writestr(item, data)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None and set(z.namelist()) == set(files)
        for name, data in files.items(): assert z.read(name) == data

def package(tag):
    version = re.search(r'const string Version = "([^"]+)"', (ROOT/'src/Program.cs').read_text(encoding='utf-8'))[1]
    tag = tag or 'v'+version
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag): raise ValueError('Use a tag such as v0.1.0')
    out = ROOT/'dist'; out.mkdir(exist_ok=True)
    if tag != 'v'+version: raise ValueError('Tag differs from installer version')
    exe = (ROOT/'build/TinkerlandsModsInstaller.exe').read_bytes()
    (out/'TinkerlandsModsInstaller.exe').write_bytes(exe)
    base = f'https://github.com/LOTARLMEN/tinkerlands-mods/releases/download/{tag}/'
    source = json.loads((ROOT/'catalog/mods.json').read_text(encoding='utf-8'))
    catalog = dict(schema=1, release=tag, installer=dict(version=version, url=base+'TinkerlandsModsInstaller.exe', sha256=sha(exe)), mods=[])
    for mod in source['mods']:
        root = ROOT/'mods'/mod['id']; info = json.loads((root/'info.json').read_text(encoding='utf-8'))
        if info['version'] != mod['version']: raise ValueError('Adapter version differs from catalog')
        script = json.loads((root/'script.json').read_text(encoding='utf-8'))
        source_file = (root/mod.get('source', 'src/main.gml')).resolve()
        if not source_file.is_relative_to(root.resolve()): raise ValueError('Script source outside mod directory')
        code = source_file.read_text(encoding='utf-8')
        if '%$%' in code or '#$#' in code: raise ValueError('Reserved encoding marker in source')
        script['code'] = code.replace('"', '%$%').replace(',', '#$#')
        adapter = out/mod['adapter']
        # Preserve the already released adapter byte-for-byte so a matching
        # manual installation can be adopted without replacing a foreign file.
        archive(adapter, {'info.json': json_bytes(info).rstrip(b'\n'), f'scripts/{script["key"]}.json': json_bytes(script).rstrip(b'\n')})
        with zipfile.ZipFile(adapter) as z:
            encoded = json.loads(z.read(f'scripts/{script["key"]}.json'))['code']
            assert encoded.replace('%$%', '"').replace('#$#', ',') == code
        files = {'mods/'+mod['adapter']: adapter.read_bytes()}
        for native in mod.get('native', []):
            name = native['name']
            if not re.fullmatch(r'[A-Za-z0-9_-]+\.dll', name): raise ValueError('Bad native DLL name')
            path = (root/native['source']).resolve()
            if not path.is_relative_to(root.resolve()): raise ValueError('DLL source outside mod directory')
            target = f'mods/native/{mod["id"]}/{name}'
            if target not in code: raise ValueError('Adapter must load the DLL from its managed relative path: '+target)
            files[target] = path.read_bytes()
        name = f'Tinkerlands-{mod["id"]}-{mod["version"]}.zip'; archive(out/name, files)
        entry = {key:mod[key] for key in ['id', 'title', 'version', 'description', 'dependencies', 'game_sha256']}
        if info.get('author'): entry['author'] = info['author']
        if mod.get('details'): entry['details'] = mod['details']
        entry.update(url=base+name, sha256=sha((out/name).read_bytes()), files=[dict(path=n, sha256=sha(b)) for n,b in files.items()])
        catalog['mods'].append(entry)
    (out/'catalog.json').write_bytes(json_bytes(catalog))
    assets = [out/'TinkerlandsModsInstaller.exe', out/'catalog.json'] + [out/entry['url'].rsplit('/',1)[1] for entry in catalog['mods']]
    (out/'SHA256SUMS.txt').write_text(''.join(f'{sha(p.read_bytes())}  {p.name}\n' for p in assets), encoding='ascii')
    print(json.dumps(dict(release=tag, assets=[dict(name=p.name, bytes=p.stat().st_size, sha256=sha(p.read_bytes())) for p in assets]), indent=2))

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--tag')
    package(p.parse_args().tag)
