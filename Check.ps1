#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SevenZipPath,
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA 'SevenZipModernMenu\installation.json')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-MenuEnvironment
$state = $null
if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Assert-MenuState $state
    if (-not $SevenZipPath) { $SevenZipPath = $state.ExternalLocation }
}
$SevenZipPath = Resolve-SevenZipPath $SevenZipPath
$compatibility = Test-SevenZipCompatibility $SevenZipPath
$package = Get-AppxPackage -Name 'Local.SevenZipModernMenu' -ErrorAction Stop
$activated = $false
$registeredDll = $null
if ($package) {
    if ($package.Status -ne 'Ok') { throw "Package status: $($package.Status)" }
    $icon = [SevenZipModernMenu.Native]::CheckPackagedActivation()
    if ([string]::IsNullOrWhiteSpace($icon)) { throw 'The registered command did not report its DLL icon path.' }
    $registeredDll = ($icon -replace ',-?\d+$','').Trim('"')
    if ($registeredDll -ne (Join-Path $SevenZipPath '7-zip.dll')) {
        throw "The registered command points to '$registeredDll', not the selected 7-Zip directory. Check the original installation state."
    }
    $activated = $true
}
[pscustomobject]@{
    SevenZipPath = $SevenZipPath
    SevenZipVersion = $compatibility.Version
    IExplorerCommandSupported = $true
    PackageRegistered = [bool]$package
    PackagedComActivation = $activated
    RegisteredDll = $registeredDll
    RecoveryStateFound = [bool]$state
    DllChangedSinceInstall = [bool]($state -and $state.DllSha256 -and $state.DllSha256 -ne $compatibility.DllSha256)
}
Write-Warning 'This checks interfaces/registration, not visible Explorer menu behavior. Nested submenus (such as CRC SHA) are limited by Explorer; use Show more options for those commands.'
