"""Run the compiled installer against release assets in an isolated fake game."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
EXE=ROOT/'build/TinkerlandsModsInstaller.exe'
def run(*args):
    p=subprocess.run([str(EXE),*map(str,args)],capture_output=True)
    text=p.stdout.decode('utf-8',errors='replace')
    if p.returncode: raise AssertionError((p.returncode,text,p.stderr.decode('utf-8',errors='replace')))
    return text
def main():
    print(run('--self-test'))
    with tempfile.TemporaryDirectory(prefix='TinkerlandsInstallerE2E-') as temporary:
        base=Path(temporary);game=base/'Игровая папка';game.mkdir();packages=base/'packages';packages.mkdir()
        pe=bytearray(512);pe[:2]=b'MZ';struct.pack_into('<I',pe,0x3c,0x80);pe[0x80:0x86]=b'PE\0\0\x64\x86'
        (game/'tinkerlands.exe').write_bytes(pe);(game/'data.win').write_bytes(b'unchanged game data')
        saves=game/'saves';saves.mkdir();(saves/'keep.sav').write_bytes(b'untouched save')
        baseline={p.relative_to(game).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in game.rglob('*') if p.is_file()}
        catalog=json.loads((ROOT/'dist/catalog.json').read_text(encoding='utf-8'))
        for mod in catalog['mods']:
            name=mod['url'].rsplit('/',1)[1];shutil.copy2(ROOT/'dist'/name,packages/name)
            mod['url']=name;mod['game_sha256']=[]
        catalog['installer']['url']='TinkerlandsModsInstaller.exe';shutil.copy2(EXE,packages/catalog['installer']['url'])
        path=packages/'catalog.json';path.write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
        result=json.loads(run('--game',game,'--catalog',path,'--list'))
        assert [mod['id'] for mod in result['mods']]==[mod['id'] for mod in catalog['mods']]
        assert all(mod['status']=='Не установлен' for mod in result['mods'])
        ids=','.join(mod['id'] for mod in catalog['mods'])
        run('--game',game,'--catalog',path,'--install',ids)
        for mod in catalog['mods']:
            for file in mod['files']:
                assert hashlib.sha256((game/file['path']).read_bytes()).hexdigest()==file['sha256'],file['path']
        assert hashlib.sha256((game/'mods/mod_menu.mod').read_bytes()).hexdigest()=='32fb7ff8e04180f989dd52e8cf3f6742b7ad2b63a80e880e190487e8cd031261'
        run('--game',game,'--remove',ids) # no catalog or network needed
        for mod in catalog['mods']:
            for file in mod['files']:
                assert not (game/file['path']).exists(),file['path']
        for name,digest in baseline.items():assert hashlib.sha256((game/name).read_bytes()).hexdigest()==digest,name
        print('PASS release package -> CLI install -> offline removal; EXE/data/saves unchanged')

if __name__=='__main__':main()
