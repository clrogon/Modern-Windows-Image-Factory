#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Golden Image - Software Installer (v1.1)
    Bakes the common software set into the THICK reference image. THIN installs nothing.

.DESCRIPTION
    Runs on the reference VM in audit mode (Ctrl+Shift+F3), as local Administrator,
    AFTER Apply-SecurityBaseline.ps1 and BEFORE Sysprep + capture. No domain required.

    Image profiles (aligned to the ORG thin/thick model):
      THIN  - No software baked into the image. Applications are layered at
              deployment time (MDT / Intune / M365 Click-to-Run). The image
              stays small and update-neutral.
      THICK - Common corporate software baked in: M365 Apps (O365ProPlus) and
              Adobe Acrobat, shipped as working examples of the two installer
              patterns you'll actually use (ODT-based and silent EXE/MSI).
              Add your own packages to $AppDefinitions below - see the
              commented template entry for the pattern.

    The CONSUMER/inbox OneDrive and Teams clients are removed offline (script 06
    removes OneDriveSetup.exe; Lists/ApprovedRemoval-Apps.txt removes the Teams
    personal app + legacy inbox MSTeams). Those bundled clients caused repeated
    deployment failures (personal-account prompts, stale tenant cache, double
    icons) that forced the support team to manually uninstall and reinstall.
    The ENTERPRISE OneDrive for Business and Teams (work) clients are different
    products - they now ship via this THICK install, as part of the M365 Apps
    ODT config (see AuditMode/Software/ODT/ODT_SemiAnnual.xml), signed in to the
    ORG tenant like the rest of Office.

    Installer binaries are staged on the BUILD SERVER in E:\Build\AuditMode\Software\
    and ride the ISO to C:\AuditMode\Software\ on the reference VM automatically
    via the $OEM$ mechanism (scripts 10 + 11). Expected layout on the VM:
        C:\AuditMode\Software\
            ODT\                  setup.exe + config + Download-OfficeSource.ps1 + Office\ (from the download helper)
            AdobeAcrobat\build\   setup.exe + Acrobat.msi (~2.7 GB, Admin Console package)
            YourApp\              drop your own MSI/EXE here and add an entry below

    The version-controlled scripts + config ship in the ZIP; binaries are staged
    into the same build-server folders after extraction (they ride the ISO).

.PARAMETER ImageProfile
    Thin or Thick. (Named ImageProfile, not Profile, to avoid shadowing the
    PowerShell automatic variable $PROFILE.)

.PARAMETER InstallerRoot
    Root where installer subfolders land on the reference VM.
    Default: C:\AuditMode\Software (rides the ISO via $OEM$)

.PARAMETER NoReboot
    Suppress the automatic reboot when an installer returns 3010 (reboot pending).

.PARAMETER DryRun
    Validate all installer paths without executing any install.

.EXAMPLE
    .\Install-ImageSoftware.ps1 -ImageProfile Thick
    .\Install-ImageSoftware.ps1 -ImageProfile Thick -DryRun
    .\Install-ImageSoftware.ps1 -ImageProfile Thin    # no-op by design

.NOTES
    Author  : Your Name - IT Solutions Architecture
    Version : 1.1 | 2026-06-03
    Target  : Windows 11 Enterprise 25H2 | MDT Reference Image Build (audit mode)
    PS      : 5.1 (no PS7 syntax). ASCII only - no smart quotes, em-dashes, box-drawing or emoji.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Thin','Thick')]
    [string]$ImageProfile,

    [string]$InstallerRoot = 'C:\AuditMode\Software',

    [string]$LogPath = 'C:\Windows\Temp\ImageBuild',

    [switch]$NoReboot,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# LOGGING (colors aligned to build suite: ERROR/WARN/OK/NEXT + default)
# -----------------------------------------------------------------------------
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "Install-ImageSoftware_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK','NEXT')][string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'NEXT'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# -----------------------------------------------------------------------------
# INSTALLER DEFINITIONS
#   Profile : 'Thick' (common image set) - THIN intentionally installs nothing.
# -----------------------------------------------------------------------------
$AppDefinitions = @(
    @{
        Name='Microsoft 365 Apps (O365ProPlus)'; Profile='Thick'; Type='ODT'
        Installer='ODT\setup.exe'; OdtXml='ODT\ODT_SemiAnnual.xml'
        Validation='HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    },
    @{
        Name='Adobe Acrobat (Admin Console package)'; Profile='Thick'; Type='EXE'
        Installer='AdobeAcrobat\build\setup.exe'
        Args='--silent'
        Validation='C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe'
    }

    # --- TEMPLATE: copy this block to add your own THICK package -------------
    # @{
    #     Name='Your App Name'; Profile='Thick'; Type='MSI'   # Type: MSI | EXE | ODT
    #     Installer='YourApp\YourApp.msi'
    #     Args='/qn /norestart REBOOT=ReallySuppress'          # MSI args shown; adjust for EXE
    #     Validation='C:\Program Files\YourApp\YourApp.exe'    # path checked post-install
    # },
    # ---------------------------------------------------------------------------
)

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------
function Test-InstallerPath {
    param([string]$RelativePath)
    $full = Join-Path $InstallerRoot $RelativePath
    if (-not (Test-Path $full)) { Write-Log "Installer not found: $full" 'ERROR'; return $false }
    return $true
}
function Invoke-MsiInstall {
    param([string]$MsiPath,[string]$Arguments,[string]$AppName)
    $msiLog = Join-Path $LogPath "$($AppName -replace '[^\w]','_').msi.log"
    $fullArgs = "/i `"$MsiPath`" $Arguments /log `"$msiLog`""
    Write-Log "  msiexec.exe $fullArgs"
    (Start-Process -FilePath 'msiexec.exe' -ArgumentList $fullArgs -Wait -PassThru -NoNewWindow).ExitCode
}
function Invoke-ExeInstall {
    param([string]$ExePath,[string]$Arguments,[string]$AppName)
    Write-Log "  `"$ExePath`" $Arguments"
    (Start-Process -FilePath $ExePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow).ExitCode
}
function Invoke-OdtInstall {
    param([string]$SetupPath,[string]$XmlPath,[string]$AppName)
    $odtDir = Split-Path $SetupPath -Parent
    $fullArgs = "/configure `"$XmlPath`""
    Write-Log "  `"$SetupPath`" $fullArgs  (WorkingDirectory: $odtDir)"
    (Start-Process -FilePath $SetupPath -ArgumentList $fullArgs -WorkingDirectory $odtDir -Wait -PassThru -NoNewWindow).ExitCode
}
function Test-Validation {
    param([string]$ValidationTarget)
    if ([string]::IsNullOrEmpty($ValidationTarget)) { return $true }
    return (Test-Path $ValidationTarget)
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
Write-Log "==================================================="
Write-Log "Golden Image Software Installer v1.1"
Write-Log "Image profile : $ImageProfile"
Write-Log "Installer root: $InstallerRoot"
Write-Log "Dry run       : $DryRun"
Write-Log "Log           : $LogFile"
Write-Log "==================================================="

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log 'Must run as Administrator. Exiting.' 'ERROR'; exit 1
}

# THIN = no software by design
if ($ImageProfile -eq 'Thin') {
    Write-Log 'THIN profile: no software is baked into the image by design.' 'OK'
    Write-Log 'Applications are layered at deployment time (MDT / Intune / C2R).' 'INFO'
    Write-Log 'Nothing to install. Proceed to Sysprep + capture.' 'NEXT'
    exit 0
}

# Build the install set for THICK
$appsToInstall = @($AppDefinitions | Where-Object { $_.Profile -eq 'Thick' })
Write-Log 'Consumer OneDrive/Teams removed offline; enterprise OneDrive for Business + Teams (work) install via M365 ODT below.' 'INFO'
Write-Log "Apps selected for THICK: $($appsToInstall.Count)"

# Pre-flight path validation (always runs)
Write-Log ''
Write-Log '[PRE-FLIGHT] Validating installer paths...'
$missing = 0
foreach ($app in $appsToInstall) {
    $paths = @($app.Installer)
    if ($app.Type -eq 'ODT' -and $app.OdtXml) { $paths += $app.OdtXml }
    foreach ($p in $paths) {
        if (Test-InstallerPath $p) { Write-Log "  [FOUND] $p" 'OK' } else { $missing++ }
    }
}
if ($missing -gt 0) { Write-Log "$missing installer(s) missing. Resolve before running. Exiting." 'ERROR'; exit 1 }
Write-Log 'Pre-flight passed.' 'OK'

if ($DryRun) { Write-Log '[DRY RUN] All paths valid. No installs executed.' 'WARN'; exit 0 }

# Install pass
$results = [System.Collections.Generic.List[hashtable]]::new()
foreach ($app in $appsToInstall) {
    Write-Log ''
    Write-Log '-----------------------------------------'
    Write-Log "Installing: $($app.Name)"
    $installerPath = Join-Path $InstallerRoot $app.Installer
    $exitCode = -1
    try {
        switch ($app.Type) {
            'MSI' { $exitCode = Invoke-MsiInstall -MsiPath $installerPath -Arguments $app.Args -AppName $app.Name }
            'EXE' {
                if ($app.Name -match 'OneDrive' -and -not (Test-Path $installerPath)) {
                    $c2r = "$env:ProgramFiles\Microsoft OneDrive\OneDriveSetup.exe"
                    if (Test-Path $c2r) { Write-Log "  OneDrive: using C2R path $c2r" 'WARN'; $installerPath = $c2r }
                    else { Write-Log '  OneDrive setup not found (staged or C2R). Skipping.' 'WARN'; $exitCode = -2; break }
                }
                $exitCode = Invoke-ExeInstall -ExePath $installerPath -Arguments $app.Args -AppName $app.Name
            }
            'ODT' { $exitCode = Invoke-OdtInstall -SetupPath $installerPath -XmlPath (Join-Path $InstallerRoot $app.OdtXml) -AppName $app.Name }
        }
    } catch { Write-Log "  Exception during install: $_" 'ERROR'; $exitCode = -99 }

    $success = $exitCode -in @(0,3010,1641)
    if ($exitCode -eq 3010) { Write-Log "  Exit $exitCode - Success (reboot required)" 'WARN' }
    elseif ($success)       { Write-Log "  Exit $exitCode - Success" 'OK' }
    else                    { Write-Log "  Exit $exitCode - FAILED" 'ERROR' }

    $validated = $false
    if ($success -and $app.Validation) {
        $validated = Test-Validation -ValidationTarget $app.Validation
        if ($validated) { Write-Log "  Validation OK: $($app.Validation)" 'OK' }
        else            { Write-Log "  Validation WARN: not found after install: $($app.Validation)" 'WARN' }
    }
    $results.Add(@{ App=$app.Name; ExitCode=$exitCode; Success=$success; Validated=$validated })
}

# Summary
Write-Log ''
Write-Log "==================================================="
Write-Log "INSTALLATION SUMMARY - Profile: $ImageProfile"
Write-Log "==================================================="
$rebootRequired = $false
foreach ($r in $results) {
    $tag = if ($r.Success) { '[OK]' } else { '[FAIL]' }
    $val = if ($r.Validated) { '(validated)' } elseif (-not $r.Success) { '' } else { '(validation skipped)' }
    Write-Log "$tag $($r.App) - Exit $($r.ExitCode) $val" $(if ($r.Success) { 'OK' } else { 'ERROR' })
    if ($r.ExitCode -eq 3010) { $rebootRequired = $true }
}
$failed = @($results | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) { Write-Log "$($failed.Count) app(s) failed. Review log: $LogFile" 'ERROR'; exit 1 }

if ($rebootRequired -and -not $NoReboot) {
    Write-Log 'One or more installers requested a reboot. Rebooting in 30s...' 'WARN'
    Write-Log "Log: $LogFile" 'OK'
    Start-Sleep -Seconds 30
    Restart-Computer -Force
} else {
    if ($rebootRequired) { Write-Log 'Reboot pending (suppressed by -NoReboot). Reboot before Sysprep.' 'WARN' }
    Write-Log "All installs completed. Log: $LogFile" 'OK'
    Write-Log 'Next: reboot if pending, then Sysprep + capture the THICK image.' 'NEXT'
    exit 0
}
