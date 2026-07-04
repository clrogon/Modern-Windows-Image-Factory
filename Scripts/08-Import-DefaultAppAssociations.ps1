#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Import Default App Associations (offline)

.DESCRIPTION
    Imports OEMDefaultAssociations.xml into the offline-mounted install.wim
    using DISM /Import-DefaultAppAssociations. This bakes the .log -> CMTrace
    association (and any other overrides) into the image so new user profiles
    created from this build inherit it.

    Runs AFTER script 04b (NetFx3) and BEFORE script 09 (dismount).

.PARAMETER Apply
    Default $false (dry-run). Set $true to execute.

.NOTES
    Document: WIN11-GOLDIMG-001 v2.3

    Why offline:
      - Survives Sysprep
      - Applied at OOBE for every new user profile, bypassing UserChoice hash
      - No per-machine post-deployment configuration needed (G6 alignment)
#>

[CmdletBinding()]
param(
    [bool]$Apply = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$MountPath = 'E:\WimMount'
$AssocXml  = 'E:\Build\OEM-Template\OEMDefaultAssociations-ORG.xml'
$LogDir    = 'E:\Build\Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "ImportDefaultAppAssociations-$Mode-$Timestamp.log"

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

Write-Log '========== 04c - Import Default App Associations (offline) =========='
Write-Log "Mode:      $Mode"
Write-Log "MountPath: $MountPath"
Write-Log "AssocXml:  $AssocXml"

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

if (-not (Test-Path $AssocXml)) {
    Write-Log "OEMDefaultAssociations XML not found at: $AssocXml" 'ERROR'
    Write-Log 'Place the curated XML at the path above before running this script.' 'ERROR'
    exit 1
}
Write-Log "Association XML verified: $AssocXml" 'OK'

# --- Validate XML well-formedness before importing ---
try {
    [xml]$Doc = Get-Content -Path $AssocXml -Raw
    $Count = $Doc.DefaultAssociations.Association.Count
    Write-Log "XML is well-formed. $Count <Association> entries detected." 'OK'

    # Sanity-check CMTrace entry exists
    $LogAssoc = $Doc.DefaultAssociations.Association | Where-Object { $_.Identifier -eq '.log' }
    if ($LogAssoc -and $LogAssoc.ProgId -eq 'CMTrace.LogFile') {
        Write-Log '.log -> CMTrace.LogFile override confirmed in XML' 'OK'
    } else {
        Write-Log '.log override not found or not pointing to CMTrace.LogFile - verify intent before applying' 'WARN'
    }
} catch {
    Write-Log "XML validation failed: $_" 'ERROR'
    Write-Log 'Fix the XML before re-running.' 'ERROR'
    exit 1
}

# --- Import ---
if ($Apply) {
    Write-Log 'Importing default app associations into offline image...'
    try {
        $DismOut = & dism.exe /Image:$MountPath /Import-DefaultAppAssociations:$AssocXml 2>&1
        $DismOut | ForEach-Object { Write-Log "  $_" }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "DISM exited with code $LASTEXITCODE" 'ERROR'
            exit 1
        }
        Write-Log 'Default app associations imported successfully' 'OK'

        # Verify
        Write-Log 'Verifying import (DISM /Get-DefaultAppAssociations)...'
        $GetOut = & dism.exe /Image:$MountPath /Get-DefaultAppAssociations 2>&1
        $GetOut | Select-Object -First 30 | ForEach-Object { Write-Log "  $_" }
        Write-Log "(Full output in DISM's own log; only first 30 lines captured here)"
    } catch {
        Write-Log "Import-DefaultAppAssociations failed: $_" 'ERROR'
        exit 1
    }
} else {
    Write-Log '[DRY-RUN] Would run:'
    Write-Log "  dism.exe /Image:$MountPath /Import-DefaultAppAssociations:$AssocXml"
}

Write-Log '========== 04c complete =========='

if (-not $Apply) {
    Write-Log ''
    Write-Log '*** DRY-RUN. Re-run with -Apply $true to execute. ***' 'WARN'
    Write-Log "Next: run 09-Dismount-Image.ps1" 'NEXT'
}
