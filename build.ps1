$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$outputFolder = Join-Path $projectRoot 'build'
New-Item -ItemType Directory -Force -Path $outputFolder | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework compiler not found' }
$files = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.cs' | ForEach-Object FullName)
$files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter '*.cs' | ForEach-Object FullName)
$executable = Join-Path $outputFolder 'TinkerlandsModsInstaller.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /utf8output /codepage:65001 "/out:$executable" /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll @files
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
Write-Output $executable
