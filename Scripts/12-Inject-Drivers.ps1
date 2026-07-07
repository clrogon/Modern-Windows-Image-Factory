#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Offline driver injection (v2.6)

.DESCRIPTION
    Injects driver packages directly into install.wim using
    DISM Add-WindowsDriver, for drivers that need to be present in the image
    itself rather than staged for post-boot PnP discovery.

    This is deliberately separate from script 10's driver handling: script 10
    copies the FULL Drivers-SCCM\ tree to C:\Drivers on the target machine so
    SetupComplete.cmd's DevicePath + pnputil scan can bind them AFTER first
    boot (see OEM-Template/README.md Task 1). That's sufficient for most
    drivers. This script exists for the drivers that can't wait that long -
    typically storage controllers or NICs a machine needs working before
    Setup's own device enumeration completes. If you don't have that
    problem, you don't need to run this script; script 10's DevicePath
    approach already covers the general case.

    Self-contained: mounts install.wim itself (it runs AFTER script 09's
    dismount -Save committed 04-08's changes), services it, and dismounts
    -Save itself. Run this AFTER 09-Dismount-Image.ps1 and BEFORE
    10-Build-OemLayer.ps1, so the drivers it injects are in the WIM that 11
    eventually packages.

    Source folder defaults to the same Drivers-SCCM\ tree script 10 already
    documents and stages (see ARCHITECTURE.md Configuration inputs) - reuse
    what's already there rather than inventing a second driver folder.
    Point -DriversSrcPath elsewhere if you want to inject a different
    (e.g. smaller, boot-critical-only) subset than what script 10 stages.

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.PARAMETER WimPath
.PARAMETER MountPath
.PARAMETER Index
    Same meaning as every other script in this pipeline; default from
    Scripts\BuildConfig.psd1.

.PARAMETER DriversSrcPath
    Folder containing driver packages (.inf trees) to inject. Default:
    <ProjectRoot>\Drivers-SCCM (same folder script 10 stages from).

.NOTES
    Document: WIN11-GOLDIMG-001 v2.6
    Run order: AFTER 09-Dismount-Image.ps1, BEFORE 10-Build-OemLayer.ps1.
    Not part of the strict 01-11 numbered sequence's mount lifecycle - it
    performs its own independent mount/service/dismount cycle rather than
    inserting into the 04-09 window, specifically to avoid renumbering any
    of the existing 01-11 scripts (see CHANGELOG.md v2.5.1 for why stale
    script-number references are treated as a real bug class in this repo,
    not a cosmetic one).
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$WimPath,
    [string]$MountPath,
    [int]$Index,
    [string]$DriversSrcPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config      = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $WimPath)        { $WimPath        = Join-Path $Config.ExtractDest 'sources\install.wim' }
if (-not $MountPath)      { $MountPath      = $Config.MountPath }
if (-not $Index)          { $Index          = $Config.WimIndex }
if (-not $DriversSrcPath) { $DriversSrcPath = Join-Path $ProjectRoot 'Drivers-SCCM' }

$LogDir    = Join-Path $ProjectRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "12-InjectDrivers-$Mode-$Timestamp.log"

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

Write-Log '========== 12 - Inject Drivers (offline, v2.6) =========='
Write-Log "Mode:        $Mode"
Write-Log "WIM:         $WimPath (index $Index)"
Write-Log "Mount:       $MountPath"
Write-Log "Drivers src: $DriversSrcPath"

# ==========================================================================
# Pre-flight
# ==========================================================================
if (-not (Test-Path $WimPath)) {
    Write-Log "install.wim not found: $WimPath" 'ERROR'
    Write-Log 'Run scripts 02-09 first (this script runs after 09-Dismount-Image.ps1).' 'ERROR'
    exit 1
}

if (-not (Test-Path $DriversSrcPath)) {
    Write-Log "Drivers source not present: $DriversSrcPath" 'ERROR'
    Write-Log 'Nothing to inject. Populate Drivers-SCCM\ or pass -DriversSrcPath, or skip this script.' 'ERROR'
    exit 1
}

$InfFiles = Get-ChildItem -Path $DriversSrcPath -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
if (-not $InfFiles -or $InfFiles.Count -eq 0) {
    Write-Log "No .inf files found under $DriversSrcPath - nothing to inject." 'ERROR'
    Write-Log 'DISM Add-WindowsDriver only binds .inf-described driver packages.' 'ERROR'
    exit 1
}
Write-Log "Found $($InfFiles.Count) .inf file(s) under $DriversSrcPath" 'OK'

$AlreadyMounted = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                  Where-Object { $_.Path -eq $MountPath }
if ($AlreadyMounted) {
    Write-Log "An image is already mounted at $MountPath" 'ERROR'
    Write-Log "  ImagePath: $($AlreadyMounted.ImagePath)" 'ERROR'
    Write-Log "  Status:    $($AlreadyMounted.MountStatus)" 'ERROR'
    Write-Log "Resolve first: Dismount-WindowsImage -Path '$MountPath' -Save (or -Discard)" 'ERROR'
    exit 1
}

if (-not (Test-Path $MountPath)) { New-Item -Path $MountPath -ItemType Directory -Force | Out-Null }
$ExistingMountContent = Get-ChildItem -Path $MountPath -Force -ErrorAction SilentlyContinue
if ($ExistingMountContent) {
    Write-Log "Mount path $MountPath is not empty and no image is reported mounted there." 'ERROR'
    Write-Log "Clean it first: Remove-Item -Path '$MountPath\*' -Recurse -Force" 'ERROR'
    exit 1
}

# ==========================================================================
# Mount, inject, dismount
# ==========================================================================
if (-not $Apply) {
    Write-Log ''
    Write-Log "[DRY-RUN] Would mount $WimPath (index $Index) at $MountPath"
    Write-Log "[DRY-RUN] Would run: Add-WindowsDriver -Path $MountPath -Driver $DriversSrcPath -Recurse"
    Write-Log "[DRY-RUN] Would dismount $MountPath -Save"
    Write-Log ''
    Write-Log '========== 12 dry-run complete =========='
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

$InjectFailed = $false
try {
    Write-Log "Injecting drivers from $DriversSrcPath (this can take several minutes)..."
    $Result = Add-WindowsDriver -Path $MountPath -Driver $DriversSrcPath -Recurse -ErrorAction Stop
    $Injected = @($Result)
    Write-Log "Injected $($Injected.Count) driver package(s)" 'OK'
    foreach ($drv in $Injected) {
        Write-Log "  $($drv.Driver) - $($drv.OriginalFileName)"
    }
} catch {
    Write-Log "Add-WindowsDriver failed: $_" 'ERROR'
    Write-Log 'Continuing to dismount -Discard so the mount point is not left stuck.' 'WARN'
    $InjectFailed = $true
}

Write-Log ''
if ($InjectFailed) {
    Write-Log 'Dismounting WITHOUT saving (injection failed)...'
    try {
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop | Out-Null
        Write-Log 'Dismounted (discarded).' 'WARN'
    } catch {
        Write-Log "Dismount -Discard also failed: $_" 'ERROR'
        Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Discard, or Clear-WindowsCorruptMountPoint" 'ERROR'
    }
    Write-Log '========== 12 FAILED =========='
    exit 1
}

Write-Log 'Dismounting and saving (this can take several minutes)...'
try {
    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
    Write-Log 'Dismount complete - driver injection committed to install.wim' 'OK'
} catch {
    Write-Log "Dismount -Save failed: $_" 'ERROR'
    Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Save, or Clear-WindowsCorruptMountPoint" 'ERROR'
    exit 1
}

Write-Log ''
Write-Log '========== 12 complete =========='
Write-Log 'Next: run 10-Build-OemLayer.ps1' 'NEXT'
