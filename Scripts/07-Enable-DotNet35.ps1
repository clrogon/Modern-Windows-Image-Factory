#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Enable .NET Framework 3.5 (offline)

.DESCRIPTION
    Enables NetFx3 feature in the offline-mounted install.wim using DISM,
    sourced from the extracted ISO's sources\sxs folder.
    Runs AFTER script 04 (OneDrive removal) and BEFORE script 09 (dismount).

.PARAMETER Apply
    Default $false (dry-run). Set $true to execute.

.NOTES
    Document: WIN11-GOLDIMG-001 v2.3
    Why offline: enabling NetFx3 online (post-deployment) requires
    internet (WU) OR a source. Baking it in offline removes that dependency
    and aligns with G2 (offline servicing principle).
#>

[CmdletBinding()]
param(
    [bool]$Apply = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration (match the rest of the build chain) ---
$Win11Version = '25H2'
$MountPath    = 'E:\WimMount'
$SxSPath      = "E:\ISO\Win11_${Win11Version}_7\sources\sxs"
$LogDir       = 'E:\Build\Logs'
$Timestamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode         = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile      = Join-Path $LogDir "07-EnableDotNet35-$Mode-$Timestamp.log"

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

Write-Log '========== 04b - Enable .NET Framework 3.5 (offline) =========='
Write-Log "Mode:      $Mode"
Write-Log "MountPath: $MountPath"
Write-Log "SxSPath:   $SxSPath"

# --- Pre-flight ---
try {
    $Mounted = Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $MountPath }
    if (-not $Mounted) {
        Write-Log "WIM not mounted at $MountPath. Run script 03 first." 'ERROR'
        exit 1
    }
    Write-Log "WIM mounted at $MountPath (status: $($Mounted.MountStatus))" 'OK'
} catch {
    Write-Log "Mount check failed: $_" 'ERROR'
    exit 1
}

if (-not (Test-Path $SxSPath)) {
    Write-Log "sxs folder not found at: $SxSPath" 'ERROR'
    Write-Log 'NetFx3 payload cannot be sourced. Verify script 01 (ExtractISO) completed.' 'ERROR'
    exit 1
}
Write-Log "sxs source verified: $SxSPath" 'OK'

# --- Check current state of NetFx3 in the offline image ---
try {
    $Feature = Get-WindowsOptionalFeature -Path $MountPath -FeatureName 'NetFx3'
    Write-Log "Current NetFx3 state in image: $($Feature.State)"
    if ($Feature.State -eq 'Enabled') {
        Write-Log 'NetFx3 is already Enabled in the image. Nothing to do.' 'OK'
        exit 0
    }
} catch {
    Write-Log "Could not query NetFx3 state: $_" 'ERROR'
    exit 1
}

# --- Enable ---
if ($Apply) {
    Write-Log 'Enabling NetFx3 in offline image (this can take a few minutes)...'
    try {
        # /All pulls dependencies; /LimitAccess prevents WU fallback
        $DismOut = & dism.exe /Image:$MountPath /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:$SxSPath 2>&1
        $DismOut | ForEach-Object { Write-Log "  $_" }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "DISM exited with code $LASTEXITCODE" 'ERROR'
            exit 1
        }

        # Verify
        $Feature = Get-WindowsOptionalFeature -Path $MountPath -FeatureName 'NetFx3'
        if ($Feature.State -eq 'Enabled') {
            Write-Log 'NetFx3 is now Enabled in the offline image' 'OK'
        } else {
            Write-Log "NetFx3 state after attempt: $($Feature.State)" 'WARN'
        }
    } catch {
        Write-Log "Enable-Feature failed: $_" 'ERROR'
        exit 1
    }
} else {
    Write-Log '[DRY-RUN] Would run:'
    Write-Log "  dism.exe /Image:$MountPath /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:$SxSPath"
}

Write-Log '========== 04b complete =========='

if (-not $Apply) {
    Write-Log ''
    Write-Log '*** DRY-RUN. Re-run with -Apply $true to execute. ***' 'WARN'
    Write-Log "Next: run 08-Import-DefaultAppAssociations.ps1" 'NEXT'
}
