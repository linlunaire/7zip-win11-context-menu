#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA 'SevenZipModernMenu\installation.json'),
    [string]$PackageDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-MenuEnvironment -Administrator
if ($PackageDirectory) {
    if ($PSBoundParameters.ContainsKey('StatePath')) { throw 'Specify -StatePath or legacy -PackageDirectory, not both.' }
    $StatePath = Join-Path $PackageDirectory 'installation.json'
}
if (-not (Test-Path -LiteralPath $StatePath)) { throw 'Installation state was not found. No package or certificate was removed.' }
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
Remove-MenuRegistration $state $StatePath
Update-MenuShell
Write-Output 'Menu unregistration finished. Original 7-Zip files were not changed.'
