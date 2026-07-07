#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Offline Features on Demand automation (v2.6)

.DESCRIPTION
    Adds Windows capabilities (Features on Demand) to install.wim via
    DISM Add-WindowsCapability, driven by a controlled list - the mirror
    image of script 04's capability REMOVAL, for capabilities you want to
    ADD instead. Entries are resolved with the same prefix-up-to-tilde
    matching script 04 uses, so Lists\ApprovedAdd-Capabilities.txt doesn't
    need to track every Windows build's exact version suffix.

    Offline FOD addition requires a local source (unlike online, where
    Windows Update supplies it automatically) - point -FodSourcePath at
    either a mounted FOD ISO/side-load image, or a folder of extracted FOD
    content. See:
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities

    Self-contained: mounts install.wim itself, services it, and dismounts
    -Save itself, same as scripts 12/13. Run AFTER 09-Dismount-Image.ps1 and
    BEFORE 10-Build-OemLayer.ps1.

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.PARAMETER FodSourcePath
    Path to a local Features on Demand source (mounted FOD ISO drive root,
    or extracted FOD content folder). Required - offline capability
    addition cannot reach Windows Update.

.PARAMETER CapabilitiesListPath
    Default: <ProjectRoot>\Lists\ApprovedAdd-Capabilities.txt

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
    [Parameter(Mandatory)]
    [string]$FodSourcePath,
    [string]$CapabilitiesListPath,
    [string]$WimPath,
    [string]$MountPath,
    [int]$Index
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config      = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $WimPath)              { $WimPath              = Join-Path $Config.ExtractDest 'sources\install.wim' }
if (-not $MountPath)            { $MountPath             = $Config.MountPath }
if (-not $Index)                { $Index                 = $Config.WimIndex }
if (-not $CapabilitiesListPath) { $CapabilitiesListPath  = Join-Path $ProjectRoot 'Lists\ApprovedAdd-Capabilities.txt' }

$LogDir    = Join-Path $ProjectRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "14-AddFeaturesOnDemand-$Mode-$Timestamp.log"

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

Write-Log '========== 14 - Add Features on Demand (offline, v2.6) =========='
Write-Log "Mode:              $Mode"
Write-Log "WIM:               $WimPath (index $Index)"
Write-Log "Mount:             $MountPath"
Write-Log "FOD source:        $FodSourcePath"
Write-Log "Capabilities list: $CapabilitiesListPath"

# ==========================================================================
# Pre-flight
# ==========================================================================
if (-not (Test-Path $WimPath)) {
    Write-Log "install.wim not found: $WimPath" 'ERROR'
    Write-Log 'Run scripts 02-09 first (this script runs after 09-Dismount-Image.ps1).' 'ERROR'
    exit 1
}

if (-not (Test-Path $FodSourcePath)) {
    Write-Log "FOD source not found: $FodSourcePath" 'ERROR'
    Write-Log 'Mount a Features on Demand ISO or point at an extracted FOD folder.' 'ERROR'
    exit 1
}

if (-not (Test-Path $CapabilitiesListPath)) {
    Write-Log "Capabilities list not found: $CapabilitiesListPath" 'ERROR'
    exit 1
}

$CapabilitiesToAdd = Get-Content $CapabilitiesListPath |
    Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
    ForEach-Object { $_.Trim() }

if ($CapabilitiesToAdd.Count -eq 0) {
    Write-Log "No capability entries in $CapabilitiesListPath (all commented/blank) - nothing to do." 'ERROR'
    exit 1
}
Write-Log "Capabilities to add (list entries): $($CapabilitiesToAdd.Count)"

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

if (-not $Apply) {
    Write-Log ''
    Write-Log "[DRY-RUN] Would mount $WimPath (index $Index) at $MountPath"
    Write-Log '[DRY-RUN] Would resolve and add these capabilities (prefix match against the mounted image, exact names not knowable until then):'
    $CapabilitiesToAdd | ForEach-Object { Write-Log "  $_" }
    Write-Log "[DRY-RUN] Would dismount $MountPath -Save"
    Write-Log ''
    Write-Log '========== 14 dry-run complete =========='
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
    Write-Log 'Enumerating capabilities in offline image...'
    $AllCaps = Get-WindowsCapability -Path $MountPath
    Write-Log "Found $($AllCaps.Count) known capabilities"

    $Stats = @{ Matched = 0; Added = 0; Skipped = 0; Failed = 0; Unmatched = @() }

    foreach ($wanted in $CapabilitiesToAdd) {
        # Same prefix-up-to-tilde matching as script 04's removal logic.
        $exact = $AllCaps | Where-Object { $_.Name -eq $wanted }
        $prefix = if (-not $exact) { $AllCaps | Where-Object { $_.Name -like "$wanted~*" -or $_.Name -like "$wanted.*" } } else { @() }
        $found = @(if ($exact) { $exact } else { $prefix })

        if ($found.Count -eq 0) {
            Write-Log ("NO MATCH  {0,-50}  not a known capability for this image - check list / wrong version suffix" -f $wanted) 'WARN'
            $Stats.Unmatched += $wanted
            continue
        }

        foreach ($cap in $found) {
            $Stats.Matched++
            if ($cap.State -eq 'Installed') {
                Write-Log ("SKIP      {0}  already installed" -f $cap.Name) 'SKIP'
                $Stats.Skipped++
                continue
            }
            Write-Log ("Adding    {0}" -f $cap.Name)
            try {
                Add-WindowsCapability -Path $MountPath -Name $cap.Name -Source $FodSourcePath -LimitAccess -ErrorAction Stop | Out-Null
                Write-Log ("  Added   {0}" -f $cap.Name) 'OK'
                $Stats.Added++
            } catch {
                Write-Log ("  FAILED  {0}: {1}" -f $cap.Name, $_) 'ERROR'
                $Stats.Failed++
            }
        }
    }

    Write-Log ''
    Write-Log "Summary: Matched=$($Stats.Matched) Added=$($Stats.Added) Skipped=$($Stats.Skipped) Failed=$($Stats.Failed) Unmatched=$($Stats.Unmatched.Count)"
    if ($Stats.Failed -gt 0) { throw "$($Stats.Failed) capability addition(s) failed - see log above" }
} catch {
    Write-Log "Feature on Demand addition failed: $_" 'ERROR'
    Write-Log 'Continuing to dismount -Discard so the mount point is not left stuck.' 'WARN'
    $StepFailed = $true
}

Write-Log ''
if ($StepFailed) {
    Write-Log 'Dismounting WITHOUT saving (one or more additions failed)...'
    try {
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop | Out-Null
        Write-Log 'Dismounted (discarded).' 'WARN'
    } catch {
        Write-Log "Dismount -Discard also failed: $_" 'ERROR'
        Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Discard, or Clear-WindowsCorruptMountPoint" 'ERROR'
    }
    Write-Log '========== 14 FAILED =========='
    exit 1
}

Write-Log 'Dismounting and saving (this can take several minutes)...'
try {
    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
    Write-Log 'Dismount complete - capabilities committed to install.wim' 'OK'
} catch {
    Write-Log "Dismount -Save failed: $_" 'ERROR'
    Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Save, or Clear-WindowsCorruptMountPoint" 'ERROR'
    exit 1
}

Write-Log ''
Write-Log '========== 14 complete =========='
Write-Log 'Next: run 10-Build-OemLayer.ps1' 'NEXT'
