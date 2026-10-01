#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SevenZipPath,
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA 'SevenZipModernMenu\installation.json')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-MenuEnvironment -NonElevated
$state = $null
if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Assert-MenuState $state
    if (-not $SevenZipPath) { $SevenZipPath = $state.ExternalLocation }
}
$SevenZipPath = Resolve-SevenZipPath $SevenZipPath
$compatibility = Test-SevenZipCompatibility $SevenZipPath
$package = Get-AppxPackage -Name 'Local.SevenZipModernMenu' -ErrorAction Stop
if ($state) {
    Assert-MenuPackage $state $package
    if ($state.Phase -eq 'Installing' -or -not $package) {
        Write-Warning "Saved recovery state needs cleanup. Run Uninstall.ps1 with -StatePath '$StatePath', then install again."
    }
}
$activated = $false
$registeredDll = $null
if ($package) {
    if ($package.Status -ne 'Ok') { throw "Package status: $($package.Status)" }
    # Read the installed manifest so diagnostics also work for the older registration-only package.
    $installedManifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
    $classId = [string]$installedManifest.Package.Applications.Application.Extensions.Extension.ComServer.SurrogateServer.Class.Id
    if ($classId -notin @('23170F69-40C1-278A-1000-000100020000','a51841e4-acd0-4a8b-b1ad-5488da4dbee6')) {
        throw 'Unexpected packaged COM class.'
    }
    $icon = [SevenZipModernMenu.Native]::CheckPackagedActivation($classId)
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
    PackageVersion = if ($package) { [string]$package.Version } else { $null }
    InstallationPhase = if ($state) { $state.Phase } else { $null }
    PackagedComActivation = $activated
    RegisteredDll = $registeredDll # Original 7-Zip backend, as in earlier diagnostic versions.
    MenuClassId = if ($package) { $classId } else { $null }
    RecoveryStateFound = [bool]$state
    DllChangedSinceInstall = [bool]($state -and $state.DllSha256 -and $state.DllSha256 -ne $compatibility.DllSha256)
}
Write-Warning 'This checks interfaces/registration, not visible Explorer menu behavior or right-click latency. Version 1.1.0 flattens CRC SHA commands into the 7-Zip submenu.'
