#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SevenZipPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$VcToolsPath,
    [string]$SdkIncludePath
)
$ErrorActionPreference = 'Stop'
$SevenZipPath = (Resolve-Path -LiteralPath $SevenZipPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $SevenZipPath '7-zip.dll'))) { throw 'Missing 7-zip.dll.' }
$programFilesX86 = (Get-Item 'Env:ProgramFiles(x86)').Value
if (-not $VcToolsPath) {
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio Build Tools with Desktop development with C++.' }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'The MSVC x64 build tools were not found.' }
    $version = (Get-Content -LiteralPath (Join-Path $vs 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt') -Raw).Trim()
    $VcToolsPath = Join-Path $vs "VC\Tools\MSVC\$version"
}
if (-not $SdkIncludePath) {
    $sdk = Get-ChildItem -LiteralPath (Join-Path $programFilesX86 'Windows Kits\10\Include') -Directory |
        Where-Object { $_.Name -match '^10\.0\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'um\ShObjIdl.h')) } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $sdk) { throw 'Windows SDK C++ headers were not found.' }
    $SdkIncludePath = $sdk.FullName
}
$sdkVersion = Split-Path $SdkIncludePath -Leaf
$sdkRoot = Split-Path (Split-Path $SdkIncludePath -Parent) -Parent
$compiler = Join-Path $VcToolsPath 'bin\Hostx64\x64\cl.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw "MSVC compiler not found: $compiler" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$dllPath = (Join-Path $SevenZipPath '7-zip.dll').Replace('\','\\').Replace('"','\"')
$fmPath = (Join-Path $SevenZipPath '7zFM.exe').Replace('\','\\').Replace('"','\"')
@"
#pragma once
constexpr wchar_t kSevenZipDll[] = L"$dllPath";
constexpr wchar_t kSevenZipIcon[] = L"$dllPath,0";
constexpr wchar_t kSevenZipFm[] = L"$fmPath";
"@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SevenZipConfig.h') -Encoding utf8
$arguments = @('/nologo','/std:c++17','/O1','/GL','/MT','/EHsc','/W4','/WX','/wd4191','/utf-8',
    '/DUNICODE','/D_UNICODE','/DWIN32_LEAN_AND_MEAN','/DNOMINMAX','/D_WIN32_WINNT=0x0A00','/guard:cf',
    "/I$VcToolsPath\include", "/I$OutputDirectory")
foreach ($part in @('shared','um','ucrt','winrt')) { $arguments += "/I$SdkIncludePath\$part" }
$linkArguments = @('/LTCG','/OPT:REF','/OPT:ICF','/DYNAMICBASE','/NXCOMPAT','/guard:cf',
    "/LIBPATH:$VcToolsPath\lib\x64", "/LIBPATH:$sdkRoot\Lib\$sdkVersion\um\x64", "/LIBPATH:$sdkRoot\Lib\$sdkVersion\ucrt\x64",
    'ole32.lib','shell32.lib','shlwapi.lib','uuid.lib')
& $compiler @arguments /LD (Join-Path $PSScriptRoot 'SevenZipMenu.cpp') "/Fo$OutputDirectory\SevenZipMenu.obj" "/Fe$OutputDirectory\SevenZipMenu.dll" /link "/DEF:$PSScriptRoot\SevenZipMenu.def" @linkArguments
if ($LASTEXITCODE -ne 0) { throw 'Native menu build failed.' }
& $compiler @arguments (Join-Path $PSScriptRoot 'Launcher.cpp') "/Fo$OutputDirectory\Launcher.obj" "/Fe$OutputDirectory\SevenZipLauncher.exe" /link /SUBSYSTEM:WINDOWS @linkArguments
if ($LASTEXITCODE -ne 0) { throw 'Native launcher build failed.' }
Write-Output "Built native adapter: $OutputDirectory\SevenZipMenu.dll"
