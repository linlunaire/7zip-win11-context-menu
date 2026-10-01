#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AdapterDll,
    [string]$SevenZipPath = 'C:\Program Files\7-Zip',
    [string]$OutputDirectory,
    [switch]$OriginalOnly,
    [switch]$Packaged
)
$ErrorActionPreference='Stop'
if (-not $OutputDirectory) { $OutputDirectory=Join-Path (Split-Path $PSScriptRoot -Parent) '.build\native-tests' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework x64 C# compiler is required for tests only.' }
$runner=Join-Path $OutputDirectory 'MenuRegression.exe'
& $compiler /nologo /target:exe /platform:x64 /r:System.Web.Extensions.dll "/out:$runner" (Join-Path $PSScriptRoot 'MenuProbe.cs') (Join-Path $PSScriptRoot 'MenuRegression.cs')
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed.' }
$fixture=Join-Path $OutputDirectory 'local file.txt'
'CRC SHA regression fixture' | Set-Content -LiteralPath $fixture -Encoding utf8
$target=if ($Packaged) { '@registered' } else { (Resolve-Path -LiteralPath $AdapterDll).Path }
$arguments=@($target,(Join-Path $SevenZipPath '7-zip.dll'),$fixture)
if ($OriginalOnly) { $arguments+='--original-only' }
& $runner @arguments
if ($LASTEXITCODE -ne 0) { throw 'Native menu regression failed.' }
