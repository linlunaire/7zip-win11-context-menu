# Run with Pester 3.4 or 4.x in Windows PowerShell 5.1. No administrator privileges required.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\Common.ps1')
$script:originalSaveState = (Get-Command Save-MenuState).ScriptBlock

Describe 'Registration recovery and certificate ownership' {
    BeforeEach {
        $script:statePath = Join-Path $TestDrive 'state\installation.json'
        $script:registered = $null
        $script:trusted = $false
        $script:otherUsers = @()
        $script:failAdd = $false
        $script:failRemove = $false
        $script:badSignature = $false
        $script:failInitialSave = $false
        $script:failFinalSave = $false
        $script:state = [pscustomobject]@{
            PackageName = 'Local.SevenZipModernMenu'
            PackageFullName = $null
            PackageVersion = '1.0.0.0'
            Publisher = 'CN=Local SevenZip Menu'
            UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            ExternalLocation = 'C:\Program Files\7-Zip'
            CertificateThumbprint = ('A' * 40)
            CertificateAdded = $true
            Phase = 'Installing'
        }
        Mock Get-AppxPackage {
            if ($AllUsers) { return $script:otherUsers }
            $script:registered
        }
        Mock Save-MenuState {
            if ($script:failInitialSave) { throw 'Injected first write failure.' }
            if ($script:failFinalSave -and $State.Phase -eq 'Installed') { throw 'Injected final write failure.' }
            & $script:originalSaveState $State $Path
        }
        Mock Add-AppxPackage {
            # Verify the recovery record is durable BEFORE changing package state.
            if (-not (Test-Path -LiteralPath $script:statePath)) { throw 'Missing recovery journal.' }
            $script:registered = [pscustomobject]@{
                PackageFullName = 'Local.SevenZipModernMenu_1.0.0.0_x64__test'
                Version = [version]'1.0.0.0'
                Publisher = 'CN=Local SevenZip Menu'
                Architecture = 'X64'
                Status = 'Ok'
            }
            if ($script:failAdd) { throw 'Injected error after partial registration.' }
        }
        Mock Remove-AppxPackage {
            if ($script:failRemove) { throw 'Injected package removal failure.' }
            $script:registered = $null
        }
        Mock Import-Certificate {
            if (-not (Test-Path -LiteralPath $script:statePath)) { throw 'Missing recovery journal.' }
            $script:trusted = $true
        }
        Mock Get-AuthenticodeSignature {
            if ($script:badSignature) { return [pscustomobject]@{Status = 'HashMismatch'} }
            [pscustomobject]@{Status = 'Valid'}
        }
        Mock Test-Path { $script:trusted } -ParameterFilter { $LiteralPath -like 'Cert:*' }
        Mock Get-Item { [pscustomobject]@{Subject = 'CN=Local SevenZip Menu'} } -ParameterFilter { $LiteralPath -like 'Cert:*' }
        Mock Remove-Item { $script:trusted = $false } -ParameterFilter { $LiteralPath -like 'Cert:*' }
    }

    It 'can uninstall after the build directory is deleted' {
        $bundle = Join-Path $TestDrive 'dist'
        New-Item -ItemType Directory -Path $bundle -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $bundle 'package.msix') -Value 'mock package'
        Set-Content -LiteralPath (Join-Path $bundle 'public.cer') -Value 'mock certificate'
        Invoke-MenuRegistration $script:state $script:statePath (Join-Path $bundle 'package.msix') (Join-Path $bundle 'public.cer')
        $saved = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
        $saved.Phase | Should Be 'Installed'
        Remove-Item -LiteralPath (Join-Path $bundle 'package.msix'), (Join-Path $bundle 'public.cer')
        Remove-Item -LiteralPath $bundle
        Remove-MenuRegistration $saved $script:statePath
        $script:registered | Should BeNullOrEmpty
        $script:trusted | Should Be $false
        (Test-Path -LiteralPath $script:statePath) | Should Be $false
    }

    It 'rolls back a partially successful Add-AppxPackage' {
        $script:failAdd = $true
        { Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer' } | Should Throw
        $script:registered | Should BeNullOrEmpty
        $script:trusted | Should Be $false
        (Test-Path -LiteralPath $script:statePath) | Should Be $false
    }

    It 'retains recoverable state when rollback itself fails' {
        $script:failAdd = $true
        $script:failRemove = $true
        { Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer' -WarningAction SilentlyContinue } | Should Throw
        $saved = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
        $saved.Phase | Should Be 'Installing'
        $script:trusted | Should Be $true
        $script:failRemove = $false
        Remove-MenuRegistration $saved $script:statePath
        $script:registered | Should BeNullOrEmpty
        $script:trusted | Should Be $false
    }

    It 'does not mutate trust or packages when the first journal write fails' {
        $script:failInitialSave = $true
        { Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer' } | Should Throw
        Assert-MockCalled Import-Certificate -Times 0 -Exactly -Scope It
        Assert-MockCalled Add-AppxPackage -Times 0 -Exactly -Scope It
    }

    It 'rolls back when saving the final installed state fails' {
        $script:failFinalSave = $true
        { Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer' } | Should Throw
        Assert-MockCalled Add-AppxPackage -Times 1 -Exactly -Scope It
        $script:registered | Should BeNullOrEmpty
        $script:trusted | Should Be $false
    }

    It 'cleans up newly added trust after signature rejection' {
        $script:badSignature = $true
        { Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer' } | Should Throw
        $script:trusted | Should Be $false
        Assert-MockCalled Add-AppxPackage -Times 0 -Exactly -Scope It
    }

    It 'preserves a certificate that existed before installation' {
        $script:trusted = $true
        $script:state.CertificateAdded = $false
        Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer'
        Remove-MenuRegistration $script:state $script:statePath
        $script:trusted | Should Be $true
        Assert-MockCalled Import-Certificate -Times 0 -Exactly -Scope It
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It -ParameterFilter { $LiteralPath -like 'Cert:*' }
    }

    It 'keeps shared certificate trust and state until other users uninstall' {
        Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer'
        $script:otherUsers = @([pscustomobject]@{PackageUserInformation = @([pscustomobject]@{InstallState = 'Installed'})})
        Remove-MenuRegistration $script:state $script:statePath
        $script:registered | Should BeNullOrEmpty
        $script:trusted | Should Be $true
        (Test-Path -LiteralPath $script:statePath) | Should Be $true
        $script:otherUsers = @()
        Remove-MenuRegistration $script:state $script:statePath
        $script:trusted | Should Be $false
    }

    It 'refuses to remove a different package version' {
        Invoke-MenuRegistration $script:state $script:statePath 'package.msix' 'public.cer'
        $script:registered.PackageFullName = 'Local.SevenZipModernMenu_2.0.0.0_x64__test'
        { Remove-MenuRegistration $script:state $script:statePath } | Should Throw
        Assert-MockCalled Remove-AppxPackage -Times 0 -Exactly -Scope It
        $script:trusted | Should Be $true
    }

    It 'rejects state belonging to a different Windows account before cleanup' {
        $script:state.UserSid = 'different-user'
        { Remove-MenuRegistration $script:state $script:statePath } | Should Throw
        Assert-MockCalled Get-AppxPackage -Times 0 -Exactly -Scope It
    }
}

Describe 'Path discovery and PE validation' {
    It 'skips an unmounted drive before trying the next installation' {
        $valid = Join-Path $TestDrive '7-Zip fallback'
        New-Item -ItemType Directory -Path $valid -Force | Out-Null
        foreach ($file in @('7-zip.dll','7zFM.exe','7zG.exe')) { Set-Content -LiteralPath (Join-Path $valid $file) -Value 'test fixture' }
        Mock Get-SevenZipCandidates { @('SevenZipMissingDrive:\7-Zip', (Join-Path $TestDrive '7-Zip fallback')) }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            (Resolve-SevenZipPath) | Should Be $valid
        } finally { $ErrorActionPreference = $previousPreference }
    }

    It 'saves relative state paths under the PowerShell working directory' {
        Push-Location $TestDrive
        try {
            & $script:originalSaveState ([pscustomobject]@{Phase = 'Installing'}) 'relative-state\installation.json'
            $saved = Get-Content -LiteralPath (Join-Path $TestDrive 'relative-state\installation.json') -Raw | ConvertFrom-Json
            $saved.Phase | Should Be 'Installing'
        } finally { Pop-Location }
    }

    It 'falls back from stale registration and normalizes trailing separators' {
        $valid = Join-Path $TestDrive '7-Zip space'
        New-Item -ItemType Directory -Path $valid -Force | Out-Null
        foreach ($file in @('7-zip.dll','7zFM.exe','7zG.exe')) { Set-Content -LiteralPath (Join-Path $valid $file) -Value 'test fixture' }
        Mock Get-SevenZipCandidates { @((Join-Path $TestDrive 'not-installed'), (Join-Path $TestDrive '7-Zip space\')) }
        (Resolve-SevenZipPath) | Should Be $valid
    }

    It 'does not silently substitute a different install for an explicit missing path' {
        { Resolve-SevenZipPath (Join-Path $TestDrive 'missing-explicit') } | Should Throw
    }

    It 'rejects truncated and invalid PE headers without loading them' {
        $invalid = Join-Path $TestDrive 'bad.dll'
        [IO.File]::WriteAllBytes($invalid, [byte[]](1,2,3))
        { Get-PeMachine $invalid } | Should Throw
        $bytes = New-Object byte[] 80
        $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[0x3c] = 0x7f
        [IO.File]::WriteAllBytes($invalid, $bytes)
        { Get-PeMachine $invalid } | Should Throw
    }
}

Describe 'Read-only diagnostics and recovery state' {
    BeforeEach {
        $script:checkPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Check.ps1'
        $script:checkStatePath = Join-Path $TestDrive 'check-state.json'
        $script:checkState = [pscustomobject]@{
            PackageName = 'Local.SevenZipModernMenu'
            PackageFullName = 'Local.SevenZipModernMenu_1.0.0.0_x64__test'
            UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            CertificateThumbprint = ('A' * 40)
            CertificateAdded = $true
            ExternalLocation = 'C:\Program Files\7-Zip'
            Phase = 'Installed'
        }
        Mock Assert-MenuEnvironment {}
        Mock Resolve-SevenZipPath { 'C:\Program Files\7-Zip' }
        Mock Test-SevenZipCompatibility { [pscustomobject]@{Version = '25.01'; DllSha256 = 'test'} }
        Mock Write-Warning {}
    }

    It 'rejects diagnostics against a package that differs from the saved installation' {
        & $script:originalSaveState $script:checkState $script:checkStatePath
        Mock Get-AppxPackage { [pscustomobject]@{PackageFullName = 'Local.SevenZipModernMenu_2.0.0.0_x64__test'; Status = 'Ok'} }
        { & $script:checkPath -StatePath $script:checkStatePath } | Should Throw 'Registered package differs from saved installation.'
    }

    It 'reports an unfinished installation even when no package is registered' {
        $script:checkState.Phase = 'Installing'
        & $script:originalSaveState $script:checkState $script:checkStatePath
        Mock Get-AppxPackage { $null }
        $report = & $script:checkPath -StatePath $script:checkStatePath
        $report.InstallationPhase | Should Be 'Installing'
        $report.PackageRegistered | Should Be $false
        Assert-MockCalled Write-Warning -Times 1 -Exactly -Scope It -ParameterFilter { $Message -like 'Saved recovery state*' }
    }
}
