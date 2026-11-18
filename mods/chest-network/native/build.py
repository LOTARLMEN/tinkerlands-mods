"""Build the Windows AMD64 storage DLL from the checked-in game ABI pins."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    native = Path(__file__).resolve().parent
    target = 'x86_64-pc-windows-gnu'
    env = os.environ.copy()
    sysroot = Path(subprocess.check_output(['rustc', '--print', 'sysroot'], text=True).strip())
    linker = sysroot / 'lib/rustlib' / target / 'bin/rust-lld.exe'
    if not linker.is_file():
        raise SystemExit(f'Установите Rust target {target} с rust-lld')
    env['CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER'] = str(linker)
    env['CARGO_TARGET_DIR'] = str(native / 'target')
    env['TINKER_STORAGE_PINS'] = str(native / 'game-pins.rs')
    env['RUSTFLAGS'] = '-C linker-flavor=ld.lld -C link-self-contained=yes -C link-arg=--no-insert-timestamp'
    flags = ['--locked', '--target', target]
    if args.offline:
        flags.append('--offline')
    subprocess.run(['cargo', 'test', *flags], cwd=native, env=env, check=True)
    subprocess.run(['cargo', 'build', '--release', *flags], cwd=native, env=env, check=True)
    output = native.parent / 'build/tinkerlands_storage.dll'
    output.parent.mkdir(exist_ok=True)
    shutil.copyfile(native / 'target' / target / 'release/tinkerlands_storage.dll', output)
    print(hashlib.sha256(output.read_bytes()).hexdigest(), output.name)


if __name__ == '__main__':
    main()
