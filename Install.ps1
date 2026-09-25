#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SevenZipPath,
    [string]$PackageDirectory = (Join-Path $PSScriptRoot 'dist'),
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA 'SevenZipModernMenu\installation.json')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-MenuEnvironment -Administrator
$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory -ErrorAction Stop).Path
$info = Get-Content -LiteralPath (Join-Path $PackageDirectory 'PackageInfo.json') -Raw | ConvertFrom-Json
if ($info.PackageName -ne 'Local.SevenZipModernMenu' -or $info.CertificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'Unexpected package metadata.'
}
$SevenZipPath = Resolve-SevenZipPath $SevenZipPath
$compatibility = Test-SevenZipCompatibility $SevenZipPath
$packagePath = Join-Path $PackageDirectory 'SevenZipModernMenu.msix'
if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $info.PackageSha256) {
    throw 'Registration package hash mismatch.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $entry = $archive.GetEntry('AppxManifest.xml')
    if (-not $entry) { throw 'The package has no manifest.' }
    $stream = $entry.Open()
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($stream, $settings)
    try { $manifest = [Xml.XmlDocument]::new(); $manifest.Load($reader) }
    finally { $reader.Dispose(); $stream.Dispose() }
} finally { $archive.Dispose() }
$identity = $manifest.Package.Identity
if ($identity.Name -ne $info.PackageName -or $identity.Publisher -ne 'CN=Local SevenZip Menu' -or
    $identity.ProcessorArchitecture -ne 'x64') { throw 'Unexpected identity inside the package.' }
$installed = Get-AppxPackage -Name $info.PackageName -ErrorAction Stop
if (Test-Path -LiteralPath $StatePath) {
    $previous = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Assert-MenuState $previous
    if ($installed -and $installed.Status -eq 'Ok' -and $previous.Phase -eq 'Installed' -and
        $previous.PackageFullName -eq $installed.PackageFullName -and
        $previous.PackageSha256 -eq $info.PackageSha256 -and $previous.ExternalLocation -eq $SevenZipPath) {
        Write-Output 'This build is already registered at the selected 7-Zip path. No changes were made.'
        return
    }
    throw "Saved installation or recovery state exists: $StatePath. Run Uninstall.ps1 with that -StatePath first."
}
if ($installed) { throw 'A menu package is already registered without matching state. Use its original uninstall procedure first.' }
$certificatePath = Join-Path $PackageDirectory 'LocalSevenZipMenu.cer'
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
try {
    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    if ($certificate.Thumbprint -ne $info.CertificateThumbprint -or
        $signature.SignerCertificate.Thumbprint -ne $info.CertificateThumbprint -or
        $certificate.Subject -ne 'CN=Local SevenZip Menu') { throw 'Unexpected signing certificate.' }
} finally { $certificate.Dispose() }
$trustPath = "Cert:\LocalMachine\TrustedPeople\$($info.CertificateThumbprint)"
$state = [pscustomobject][ordered]@{
    PackageName = $info.PackageName
    PackageFullName = $null
    PackageVersion = [string]$identity.Version
    Publisher = [string]$identity.Publisher
    PackageSha256 = $info.PackageSha256
    UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    ExternalLocation = $SevenZipPath
    SevenZipVersion = $compatibility.Version
    DllSha256 = $compatibility.DllSha256
    CertificateThumbprint = $info.CertificateThumbprint
    CertificateAdded = -not (Test-Path -LiteralPath $trustPath)
    Phase = 'Installing'
}
Invoke-MenuRegistration $state $StatePath $packagePath $certificatePath
Update-MenuShell
Write-Output "Registered 7-Zip. Recovery state: $StatePath. Run Check.ps1, then check the menu in Explorer."
