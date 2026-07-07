#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Optional offline Microsoft Store restoration (v2.6)

.DESCRIPTION
    Lists/README.md already tells operators not to add Microsoft Store to
    Lists\ApprovedRemoval-Apps.txt (Store is needed for Company Portal,
    Terminal, and other LOB delivery). This script exists for the recovery
    path: a custom/inherited removal list stripped it anyway, or a
    third-party debloat pass ran before this pipeline touched the image, and
    you want it back without re-extracting the ISO from scratch.

    Restores Microsoft Store via DISM Add-AppxProvisionedPackage, from a
    locally staged export of the Store package + license + framework
    dependencies (VCLibs, UI.Xaml, etc.) - the same offline procedure
    Microsoft documents for restoring an inbox AppX package. Nothing is
    downloaded; you provide the export.

    Source layout expected (create as needed - not shipped):
        <ProjectRoot>\Software\MicrosoftStore\
            *.appxbundle or *.msixbundle   (the Store package itself)
            *.xml                          (its license file)
            Dependencies\*.appx / *.msix   (framework packages it depends on)

    To produce that export from a reference machine that still has Store,
    see Microsoft's documented offline AppX restoration procedure (export
    via Get-AppxPackage -AllUsers Microsoft.WindowsStore and
    Get-AppxPackageManifest, or pull the bundle+license+deps from an
    unmodified Windows 11 ISO's provisioning data).

    Self-contained: mounts install.wim itself, services it, and dismounts
    -Save itself, same as scripts 12-14. Run AFTER 09-Dismount-Image.ps1 and
    BEFORE 10-Build-OemLayer.ps1.

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.PARAMETER StoreSourcePath
    Default: <ProjectRoot>\Software\MicrosoftStore

.PARAMETER WimPath
.PARAMETER MountPath
.PARAMETER Index
    Same meaning as every other script in this pipeline; default from
    Scripts\BuildConfig.psd1.

.NOTES
    Document: WIN11-GOLDIMG-001 v2.6
    Run order: AFTER 09-Dismount-Image.ps1, BEFORE 10-Build-OemLayer.ps1.
    Independent mount/service/dismount cycle, same reasoning as script 12
    (see its .NOTES) - avoids renumbering the existing 01-11 sequence.
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$StoreSourcePath,
    [string]$WimPath,
    [string]$MountPath,
    [int]$Index
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config      = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $WimPath)         { $WimPath         = Join-Path $Config.ExtractDest 'sources\install.wim' }
if (-not $MountPath)       { $MountPath       = $Config.MountPath }
if (-not $Index)           { $Index           = $Config.WimIndex }
if (-not $StoreSourcePath) { $StoreSourcePath = Join-Path $ProjectRoot 'Software\MicrosoftStore' }

$LogDir    = Join-Path $ProjectRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "15-RestoreMicrosoftStore-$Mode-$Timestamp.log"

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $Line -ForegroundColor Red }
        'WARN'  { Write-Host $Line -ForegroundColor Yellow }
        'OK'    { Write-Host $Line -ForegroundColor Green }
        'NEXT'  { Write-Host $Line -ForegroundColor Cyan }
        default { Write-Host $Line }
    }
}

Write-Log '========== 15 - Restore Microsoft Store (offline, optional, v2.6) =========='
Write-Log "Mode:        $Mode"
Write-Log "WIM:         $WimPath (index $Index)"
Write-Log "Mount:       $MountPath"
Write-Log "Store src:   $StoreSourcePath"

# ==========================================================================
# Pre-flight
# ==========================================================================
if (-not (Test-Path $WimPath)) {
    Write-Log "install.wim not found: $WimPath" 'ERROR'
    Write-Log 'Run scripts 02-09 first (this script runs after 09-Dismount-Image.ps1).' 'ERROR'
    exit 1
}

if (-not (Test-Path $StoreSourcePath)) {
    Write-Log "Microsoft Store source not present: $StoreSourcePath" 'ERROR'
    Write-Log 'See this script''s header comment for the expected layout and how to produce it.' 'ERROR'
    exit 1
}

$BundleFile = Get-ChildItem -Path $StoreSourcePath -Include '*.appxbundle', '*.msixbundle' -File -ErrorAction SilentlyContinue | Select-Object -First 1
$LicenseFile = Get-ChildItem -Path $StoreSourcePath -Filter '*.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
$DepsPath = Join-Path $StoreSourcePath 'Dependencies'
$DepFiles = @()
if (Test-Path $DepsPath) {
    $DepFiles = @(Get-ChildItem -Path $DepsPath -Include '*.appx', '*.msix' -File -Recurse -ErrorAction SilentlyContinue)
}

if (-not $BundleFile)  { Write-Log "No *.appxbundle/*.msixbundle found under $StoreSourcePath" 'ERROR' }
if (-not $LicenseFile) { Write-Log "No license *.xml found under $StoreSourcePath" 'ERROR' }
if (-not $BundleFile -or -not $LicenseFile) { exit 1 }

Write-Log "Bundle:  $($BundleFile.Name)" 'OK'
Write-Log "License: $($LicenseFile.Name)" 'OK'
if ($DepFiles.Count -eq 0) {
    Write-Log "No dependency packages found under $DepsPath - proceeding without them (Add-WindowsPackage will fail if the Store bundle actually needs one)." 'WARN'
} else {
    Write-Log "Dependencies: $($DepFiles.Count) package(s)" 'OK'
    $DepFiles | ForEach-Object { Write-Log "  $($_.Name)" }
}

$AlreadyMounted = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                  Where-Object { $_.Path -eq $MountPath }
if ($AlreadyMounted) {
    Write-Log "An image is already mounted at $MountPath - resolve first (Dismount-WindowsImage -Save/-Discard)." 'ERROR'
    exit 1
}

if (-not (Test-Path $MountPath)) { New-Item -Path $MountPath -ItemType Directory -Force | Out-Null }
if (Get-ChildItem -Path $MountPath -Force -ErrorAction SilentlyContinue) {
    Write-Log "Mount path $MountPath is not empty and nothing is reported mounted there. Clean it first." 'ERROR'
    exit 1
}

# ==========================================================================
# Mount, restore, dismount
# ==========================================================================
if (-not $Apply) {
    Write-Log ''
    Write-Log "[DRY-RUN] Would mount $WimPath (index $Index) at $MountPath"
    Write-Log "[DRY-RUN] Would run: Add-AppxProvisionedPackage -Path $MountPath -PackagePath $($BundleFile.FullName) -LicensePath $($LicenseFile.FullName) -DependencyPackagePath <$($DepFiles.Count) file(s)>"
    Write-Log "[DRY-RUN] Would dismount $MountPath -Save"
    Write-Log ''
    Write-Log '========== 15 dry-run complete =========='
    Write-Log '*** DRY-RUN. Re-run with -Apply to execute. ***' 'WARN'
    exit 0
}

Write-Log ''
Write-Log "Mounting WIM at $MountPath..."
try {
    Mount-WindowsImage -ImagePath $WimPath -Index $Index -Path $MountPath | Out-Null
    Write-Log 'Mount succeeded' 'OK'
} catch {
    Write-Log "Mount failed: $_" 'ERROR'
    exit 1
}

$StepFailed = $false
try {
    Write-Log 'Restoring Microsoft Store...'
    $AddParams = @{
        Path        = $MountPath
        PackagePath = $BundleFile.FullName
        LicensePath = $LicenseFile.FullName
        ErrorAction = 'Stop'
    }
    if ($DepFiles.Count -gt 0) { $AddParams.DependencyPackagePath = @($DepFiles.FullName) }
    Add-AppxProvisionedPackage @AddParams | Out-Null
    Write-Log 'Microsoft Store restored' 'OK'
} catch {
    Write-Log "Add-AppxProvisionedPackage failed: $_" 'ERROR'
    Write-Log 'Continuing to dismount -Discard so the mount point is not left stuck.' 'WARN'
    $StepFailed = $true
}

Write-Log ''
if ($StepFailed) {
    Write-Log 'Dismounting WITHOUT saving (restoration failed)...'
    try {
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop | Out-Null
        Write-Log 'Dismounted (discarded).' 'WARN'
    } catch {
        Write-Log "Dismount -Discard also failed: $_" 'ERROR'
        Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Discard, or Clear-WindowsCorruptMountPoint" 'ERROR'
    }
    Write-Log '========== 15 FAILED =========='
    exit 1
}

Write-Log 'Dismounting and saving (this can take several minutes)...'
try {
    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
    Write-Log 'Dismount complete - Microsoft Store committed to install.wim' 'OK'
} catch {
    Write-Log "Dismount -Save failed: $_" 'ERROR'
    Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Save, or Clear-WindowsCorruptMountPoint" 'ERROR'
    exit 1
}

Write-Log ''
Write-Log '========== 15 complete =========='
Write-Log 'Next: run 10-Build-OemLayer.ps1' 'NEXT'
