"""Verify the published .NET image can be renamed and replaced while mapped.

Runs the public 0.1.1 updater implementation via reflection in a disposable
PowerShell process, targeting only a downloaded EXE in a generated temp folder.
The game and the developer's installer EXE are never replacement targets.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=r'''
param([string]$OldExe,[string]$NewExe)
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFile($OldExe)
$release=[Activator]::CreateInstance($assembly.GetType('TinkerlandsMods.InstallerRelease'))
$release.version=([version][Diagnostics.FileVersionInfo]::GetVersionInfo($NewExe).FileVersion).ToString(3)
$sha=[Security.Cryptography.SHA256]::Create()
$release.sha256=([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($NewExe)))).Replace('-','').ToLowerInvariant()
$start=[Action[string]]{
    param($UpdatedExe)
    $settings=New-Object Diagnostics.ProcessStartInfo
    $settings.FileName=$UpdatedExe
    $settings.Arguments='--version'
    $settings.UseShellExecute=$false
    $settings.CreateNoWindow=$true
    $settings.RedirectStandardOutput=$true
    $process=[Diagnostics.Process]::Start($settings)
    $output=$process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or $output.Trim() -ne $release.version) {throw 'Updated installer did not execute'}
}
$method=$assembly.GetType('TinkerlandsMods.SelfUpdate').GetMethod('Swap')
$arguments=[object[]]@($OldExe,[IO.File]::ReadAllBytes($NewExe),$release,$start)
$method.Invoke($null,$arguments)
if (-not (Test-Path -LiteralPath ($OldExe+'.previous.exe'))) {throw 'Old mapped EXE was not retained'}
Write-Output "PASS published 0.1.1 mapped assembly -> replace -> execute $($release.version)"
'''

def main():
    request=urllib.request.Request('https://github.com/LOTARLMEN/tinkerlands-mods/releases/download/v0.1.1/TinkerlandsModsInstaller.exe',headers={'User-Agent':'TinkerlandsInstallerUpdateTest'})
    old=urllib.request.urlopen(request,timeout=30).read()
    assert hashlib.sha256(old).hexdigest()=='9351b78a2d4427ea342dddfff88997edc4b074c61b5643d984ea82bb9ad43df3'
    with tempfile.TemporaryDirectory(prefix='TinkerlandsMappedUpdate-') as temporary:
        directory=Path(temporary);target=directory/'TinkerlandsModsInstaller.exe';target.write_bytes(old)
        script=directory/'test.ps1';script.write_text(SCRIPT,encoding='ascii')
        powershell=Path(os.environ['WINDIR'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
        result=subprocess.run([str(powershell),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(script),'-OldExe',str(target),'-NewExe',str(ROOT/'dist/TinkerlandsModsInstaller.exe')],capture_output=True,timeout=60)
        print(result.stdout.decode('utf-8',errors='replace'))
        if result.returncode:raise AssertionError(result.stderr.decode('utf-8',errors='replace'))
        assert hashlib.sha256(target.read_bytes()).digest()==hashlib.sha256((ROOT/'dist/TinkerlandsModsInstaller.exe').read_bytes()).digest()

if __name__=='__main__':main()
