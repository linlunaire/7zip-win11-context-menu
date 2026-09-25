function Assert-MenuEnvironment {
    param([switch]$Administrator, [switch]$NonElevated)
    $build = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop
    if ([int]$build -lt 22000 -or -not [Environment]::Is64BitProcess -or
        $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        throw 'Use 64-bit PowerShell on Windows 11 x64. ARM64 and 32-bit processes are not supported.'
    }
    if ($Administrator -or $NonElevated) {
        $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($Administrator -and -not $elevated) {
            throw 'Open PowerShell as administrator using the same Windows account, then run this script again.'
        }
        if ($NonElevated -and $elevated) {
            throw 'Run Check.ps1 in a normal, non-administrator PowerShell window to match the Explorer user context.'
        }
    }
}

function Initialize-MenuNative {
    if (-not ('SevenZipModernMenu.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs') }
}

function Get-SevenZipCandidates {
    # Prefer machine registration; do not automatically load DLLs selected by HKCU/App Paths.
    $registration = Get-ItemProperty 'HKLM:\SOFTWARE\7-Zip' -ErrorAction SilentlyContinue
    foreach ($name in @('Path64', 'Path')) {
        if ($registration -and $registration.$name) { [string]$registration.$name }
    }
    Join-Path $env:ProgramFiles '7-Zip'
}

function Resolve-SevenZipPath {
    param([string]$Path)
    $explicit = -not [string]::IsNullOrWhiteSpace($Path)
    $candidates = if ($explicit) { @($Path) } else { @(Get-SevenZipCandidates | Select-Object -Unique) }
    foreach ($candidate in $candidates) {
        $complete = Test-Path -LiteralPath $candidate -PathType Container
        if ($complete) {
            foreach ($file in @('7-zip.dll', '7zFM.exe', '7zG.exe')) {
                if (-not (Test-Path -LiteralPath (Join-Path $candidate $file) -PathType Leaf)) { $complete = $false }
            }
        }
        if ($complete) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            if ($resolved.Length -gt [IO.Path]::GetPathRoot($resolved).Length) { $resolved = $resolved.TrimEnd('\') }
            return $resolved
        }
        if ($explicit) { throw "Incomplete 7-Zip installation: $candidate. Expected 7-zip.dll, 7zFM.exe and 7zG.exe." }
    }
    throw '7-Zip was not found. Install it or specify -SevenZipPath explicitly.'
}

function Get-PeMachine {
    param([string]$Path)
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.BaseStream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw "Invalid PE file: $Path" }
        $reader.BaseStream.Position = 0x3c
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt $reader.BaseStream.Length - 6) { throw "Invalid PE header: $Path" }
        $reader.BaseStream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE signature: $Path" }
        $reader.ReadUInt16()
    } finally { $reader.Dispose() }
}

function Test-SevenZipCompatibility {
    param([string]$Path)
    foreach ($file in @('7-zip.dll', '7zFM.exe', '7zG.exe')) {
        if ((Get-PeMachine (Join-Path $Path $file)) -ne 0x8664) { throw "Expected x64 7-Zip binary: $file" }
    }
    Initialize-MenuNative
    try { [SevenZipModernMenu.Native]::CheckLibrary((Join-Path $Path '7-zip.dll')) }
    catch { throw "This 7-Zip DLL cannot provide IExplorerCommand: $($_.Exception.Message)" }
    [pscustomobject]@{
        Path = $Path
        Version = (Get-Item -LiteralPath (Join-Path $Path '7-zip.dll')).VersionInfo.FileVersion
        DllSha256 = (Get-FileHash -LiteralPath (Join-Path $Path '7-zip.dll') -Algorithm SHA256).Hash
    }
}

function Save-MenuState {
    param($State, [string]$Path)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ('.installation-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding utf8
        # Replace within the same directory without deleting the previous recovery record first.
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

function Assert-MenuState {
    param($State)
    if ($State.PackageName -ne 'Local.SevenZipModernMenu' -or
        $State.CertificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$' -or
        $State.CertificateAdded -isnot [bool] -or
        $State.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        throw 'Invalid installation state or a different Windows account. No changes were made.'
    }
    if (-not $State.PackageFullName -and
        (-not $State.PackageVersion -or $State.Publisher -ne 'CN=Local SevenZip Menu')) {
        throw 'Installation state does not identify the expected package.'
    }
}

function Assert-MenuPackage {
    param($State, $Package)
    if ($Package) {
        if ($State.PackageFullName) {
            if ($Package.PackageFullName -ne $State.PackageFullName) { throw 'Registered package differs from saved installation.' }
        } elseif ([string]$Package.Version -ne $State.PackageVersion -or
            $Package.Publisher -ne $State.Publisher -or [string]$Package.Architecture -ne 'X64') {
            throw 'Pending installation state does not match the registered package.'
        }
    }
}

function Remove-MenuRegistration {
    param($State, [string]$StatePath)
    Assert-MenuState $State
    $installed = Get-AppxPackage -Name $State.PackageName -ErrorAction Stop
    Assert-MenuPackage $State $installed
    if ($installed) {
        Remove-AppxPackage -Package $installed.PackageFullName -ErrorAction Stop
        if (Get-AppxPackage -Name $State.PackageName -ErrorAction Stop) { throw 'Package is still registered. Recovery state was retained.' }
    }
    $trustPath = "Cert:\LocalMachine\TrustedPeople\$($State.CertificateThumbprint)"
    if ($State.CertificateAdded -and (Test-Path -LiteralPath $trustPath)) {
        # A machine-wide certificate may still support another user's package.
        $otherUsers = @(Get-AppxPackage -AllUsers -Name $State.PackageName -ErrorAction Stop | Where-Object {
            @($_.PackageUserInformation | Where-Object { [string]$_.InstallState -eq 'Installed' }).Count -gt 0
        })
        if ($otherUsers.Count) {
            Write-Warning "Menu removed for this account. Another account still uses the package; certificate and recovery state retained at $StatePath. Run Uninstall.ps1 again after their uninstall."
            return
        }
        $trusted = Get-Item -LiteralPath $trustPath -ErrorAction Stop
        if ($trusted.Subject -ne 'CN=Local SevenZip Menu') { throw 'Certificate subject mismatch. Recovery state was retained.' }
        Remove-Item -LiteralPath $trustPath -ErrorAction Stop
    }
    Remove-Item -LiteralPath $StatePath -ErrorAction Stop
}

function Update-MenuShell {
    try { Initialize-MenuNative; [SevenZipModernMenu.Native]::RefreshShell() }
    catch { Write-Warning 'Could not notify Explorer. Sign out and back in if the menu has not refreshed.' }
}

function Invoke-MenuRegistration {
    param($State, [string]$StatePath, [string]$PackagePath, [string]$CertificatePath)
    # Persist recovery information before the first certificate/package mutation.
    Save-MenuState $State $StatePath
    try {
        if ($State.CertificateAdded) {
            Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
        }
        if ((Get-AuthenticodeSignature -LiteralPath $PackagePath).Status -ne 'Valid') {
            throw 'The package signature is not valid after trusting its local certificate.'
        }
        Add-AppxPackage -Path $PackagePath -ExternalLocation $State.ExternalLocation -ErrorAction Stop
        $installed = Get-AppxPackage -Name $State.PackageName -ErrorAction Stop
        if (-not $installed -or $installed.Status -ne 'Ok') { throw 'Package registration did not finish successfully.' }
        $State.PackageFullName = $installed.PackageFullName
        $State.Phase = 'Installed'
        Save-MenuState $State $StatePath
    } catch {
        $installationError = $_
        try { Remove-MenuRegistration $State $StatePath }
        catch { Write-Warning "Rollback incomplete: $($_.Exception.Message). Recovery state remains at $StatePath." }
        throw $installationError
    }
}
