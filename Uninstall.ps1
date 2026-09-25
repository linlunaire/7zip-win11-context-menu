#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param([string]$PackageDirectory = (Join-Path $PSScriptRoot 'dist'))

$ErrorActionPreference = 'Stop'
$stateFile = Join-Path $PackageDirectory 'installation.json'
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
if ($state.PackageName -ne 'Local.SevenZipModernMenu') { throw 'Unexpected package identity.' }
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $state.UserSid) {
    throw 'Use the Windows account that installed this menu.'
}
$installed = Get-AppxPackage -Name $state.PackageName
if ($installed) {
    if ($installed.PackageFullName -ne $state.PackageFullName) { throw 'The registered package differs from the saved installation.' }
    $installed | Remove-AppxPackage -ErrorAction Stop
}
$trustPath = "Cert:\LocalMachine\TrustedPeople\$($state.CertificateThumbprint)"
if ($state.CertificateAdded -and (Test-Path -LiteralPath $trustPath)) {
    Remove-Item -LiteralPath $trustPath
}
Remove-Item -LiteralPath $stateFile
Write-Output 'Removed this menu registration and its added certificate. Original 7-Zip files were not changed.'
