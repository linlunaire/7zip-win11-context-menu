#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$SevenZipPath = (Join-Path $env:ProgramFiles '7-Zip'),
    [string]$PackageDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
$info = Get-Content -LiteralPath (Join-Path $PackageDirectory 'PackageInfo.json') -Raw | ConvertFrom-Json
if ($info.PackageName -ne 'Local.SevenZipModernMenu') { throw 'Unexpected package identity.' }
if (Get-AppxPackage -Name $info.PackageName) {
    throw 'This menu is already registered. Use its original uninstall script before installing another build.'
}
if (Test-Path -LiteralPath (Join-Path $PackageDirectory 'installation.json')) {
    throw 'Installation state already exists. Finish uninstalling that installation first.'
}
$SevenZipPath = (Resolve-Path -LiteralPath $SevenZipPath).Path
foreach ($name in @('7-zip.dll', '7zFM.exe', '7zG.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SevenZipPath $name) -PathType Leaf)) { throw "Missing 7-Zip file: $name" }
}
$packagePath = Join-Path $PackageDirectory 'SevenZipModernMenu.msix'
if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $info.PackageSha256) {
    throw 'Registration package hash mismatch.'
}
$certificatePath = Join-Path $PackageDirectory 'LocalSevenZipMenu.cer'
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
$signature = Get-AuthenticodeSignature -LiteralPath $packagePath
if ($certificate.Thumbprint -ne $info.CertificateThumbprint -or
    $signature.SignerCertificate.Thumbprint -ne $info.CertificateThumbprint -or
    $certificate.Subject -ne 'CN=Local SevenZip Menu') { throw 'Unexpected signing certificate.' }
$trustPath = "Cert:\LocalMachine\TrustedPeople\$($info.CertificateThumbprint)"
$certificateAdded = $false
try {
    if (-not (Test-Path -LiteralPath $trustPath)) {
        Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
        $certificateAdded = $true
    }
    if ((Get-AuthenticodeSignature -LiteralPath $packagePath).Status -ne 'Valid') {
        throw 'The package signature is not valid after trusting its local certificate.'
    }
    Add-AppxPackage -Path $packagePath -ExternalLocation $SevenZipPath -ErrorAction Stop
    $installed = Get-AppxPackage -Name $info.PackageName
    if (-not $installed -or $installed.Status -ne 'Ok') { throw 'Package registration did not finish successfully.' }
    [ordered]@{
        PackageName = $info.PackageName
        PackageFullName = $installed.PackageFullName
        UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        ExternalLocation = $SevenZipPath
        CertificateThumbprint = $info.CertificateThumbprint
        CertificateAdded = $certificateAdded
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PackageDirectory 'installation.json') -Encoding utf8
    Write-Output 'Registered 7-Zip for the current Windows account. Right-click a file or folder to check the menu.'
} catch {
    if ($certificateAdded -and -not (Get-AppxPackage -Name $info.PackageName)) {
        Remove-Item -LiteralPath $trustPath -ErrorAction SilentlyContinue
    }
    throw
}
