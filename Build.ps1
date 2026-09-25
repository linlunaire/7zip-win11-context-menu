#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SevenZipPath,
    [string]$SdkBinPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-MenuEnvironment
$SevenZipPath = Resolve-SevenZipPath $SevenZipPath
$compatibility = Test-SevenZipCompatibility $SevenZipPath
$sevenZipExe = Join-Path $SevenZipPath '7zFM.exe'
Write-Output "Compatible 7-Zip $($compatibility.Version): $SevenZipPath"
if (-not $SdkBinPath) {
    $sdkRegistration = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
    $sdkRoot = if ($sdkRegistration.KitsRoot10) { Join-Path $sdkRegistration.KitsRoot10 'bin' }
        else { Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin' }
    $sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^10\.0\.\d+\.\d+$' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'x64\makeappx.exe')) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'x64\signtool.exe'))
        } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $sdk) { throw 'Install Windows SDK packaging/signing tools, or provide -SdkBinPath.' }
    $SdkBinPath = Join-Path $sdk.FullName 'x64'
}
$makeAppx = Join-Path $SdkBinPath 'makeappx.exe'
$signTool = Join-Path $SdkBinPath 'signtool.exe'
foreach ($tool in @($makeAppx, $signTool)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "SDK tool not found: $tool" }
}
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'installation.json')) {
    throw 'This directory contains installation state. Uninstall first or use a different -OutputDirectory.'
}
if ((Test-Path -LiteralPath $OutputDirectory) -and @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count) {
    throw 'Build output must be empty. Choose a new output directory so stale payloads and signing identities cannot be reused.'
}
$payload = Join-Path $OutputDirectory 'payload'
New-Item -ItemType Directory -Path (Join-Path $payload 'Assets') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package\AppxManifest.xml') -Destination $payload
Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Icon]::ExtractAssociatedIcon($sevenZipExe)
$bitmap = $icon.ToBitmap()
try { $bitmap.Save((Join-Path $payload 'Assets\Logo.png'), [Drawing.Imaging.ImageFormat]::Png) }
finally { $bitmap.Dispose(); $icon.Dispose() }
$packagePath = Join-Path $OutputDirectory 'SevenZipModernMenu.msix'
& $makeAppx pack /o /d $payload /nv /p $packagePath
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx failed.' }

# Generate a distinct local signing key. Do not export or distribute the private key.
$certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Local SevenZip Menu' `
    -FriendlyName 'Local 7-Zip modern menu registration' -CertStoreLocation Cert:\CurrentUser\My `
    -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable `
    -NotAfter (Get-Date).AddYears(5)
$thumbprint = $certificate.Thumbprint
try {
    Export-Certificate -Cert $certificate -FilePath (Join-Path $OutputDirectory 'LocalSevenZipMenu.cer') | Out-Null
    & $signTool sign /fd SHA256 /s My /sha1 $thumbprint $packagePath
    if ($LASTEXITCODE -ne 0) { throw 'SignTool failed.' }
} finally {
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -DeleteKey
}
[ordered]@{
    PackageName = 'Local.SevenZipModernMenu'
    PackageFile = 'SevenZipModernMenu.msix'
    CertificateFile = 'LocalSevenZipMenu.cer'
    CertificateThumbprint = $thumbprint
    PackageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    TestedSevenZipVersion = $compatibility.Version
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'PackageInfo.json') -Encoding utf8
Write-Output "Built locally signed registration package in: $OutputDirectory"
Write-Output 'No certificate was trusted and no menu was installed by this build.'
