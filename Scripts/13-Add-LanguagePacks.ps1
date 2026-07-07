#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Offline language pack integration (v2.6)

.DESCRIPTION
    Injects one or more Windows language pack CABs into install.wim via
    DISM Add-WindowsPackage, and optionally sets the injected language as
    the image's default (DISM /Set-SKUIntlDefaults) so new user profiles
    inherit it without a per-machine language switch after deployment.

    Source layout expected (create as needed - not shipped, like
    Drivers-SCCM\):
        <ProjectRoot>\LanguagePacks\<LanguageTag>\*.cab
    e.g. LanguagePacks\pt-AO\Microsoft-Windows-Client-Language-Pack_x64_pt-ao.cab
    plus any Feature-on-Demand satellite CABs you want alongside it (Basic,
    TextToSpeech, Handwriting, OCR) - every *.cab under that folder is
    injected.

    Self-contained: mounts install.wim itself, services it, and dismounts
    -Save itself, same as script 12. Run AFTER 09-Dismount-Image.ps1 and
    BEFORE 10-Build-OemLayer.ps1.

    Deliberately has no hardcoded default language - unlike
    AuditMode/Apply-PostInstallCustomization.ps1 (which is this repo's own
    Angola-specific deployment example), this is a general-purpose
    build-server script. -LanguageTag is required.

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.PARAMETER LanguageTag
    BCP-47 language tag matching a subfolder of LanguagePacks\, e.g. 'pt-AO'.
    Required.

.PARAMETER SetAsDefault
    Also run DISM /Set-SKUIntlDefaults:<LanguageTag> after injecting, making
    it the image's default UI/system/user locale. Omit to add the language
    pack as a secondary, selectable language only.

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
    [string]$LanguageTag,
    [switch]$SetAsDefault,
    [string]$WimPath,
    [string]$MountPath,
    [int]$Index
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config      = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $WimPath)   { $WimPath   = Join-Path $Config.ExtractDest 'sources\install.wim' }
if (-not $MountPath) { $MountPath = $Config.MountPath }
if (-not $Index)     { $Index     = $Config.WimIndex }
$LangPackSrc = Join-Path $ProjectRoot "LanguagePacks\$LanguageTag"

$LogDir    = Join-Path $ProjectRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "13-AddLanguagePacks-$Mode-$Timestamp.log"

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

Write-Log '========== 13 - Add Language Packs (offline, v2.6) =========='
Write-Log "Mode:          $Mode"
Write-Log "Language tag:  $LanguageTag"
Write-Log "Set as default: $SetAsDefault"
Write-Log "WIM:           $WimPath (index $Index)"
Write-Log "Mount:         $MountPath"
Write-Log "Language src:  $LangPackSrc"

# ==========================================================================
# Pre-flight
# ==========================================================================
if (-not (Test-Path $WimPath)) {
    Write-Log "install.wim not found: $WimPath" 'ERROR'
    Write-Log 'Run scripts 02-09 first (this script runs after 09-Dismount-Image.ps1).' 'ERROR'
    exit 1
}

if (-not (Test-Path $LangPackSrc)) {
    Write-Log "Language pack source not present: $LangPackSrc" 'ERROR'
    Write-Log "Create LanguagePacks\$LanguageTag\ and place the language pack CAB(s) there first." 'ERROR'
    exit 1
}

$CabFiles = Get-ChildItem -Path $LangPackSrc -Filter '*.cab' -Recurse -ErrorAction SilentlyContinue
if (-not $CabFiles -or $CabFiles.Count -eq 0) {
    Write-Log "No .cab files found under $LangPackSrc - nothing to inject." 'ERROR'
    exit 1
}
Write-Log "Found $($CabFiles.Count) CAB(s) to inject:" 'OK'
$CabFiles | ForEach-Object { Write-Log "  $($_.Name)" }

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
# Mount, inject, (optionally) set default, dismount
# ==========================================================================
if (-not $Apply) {
    Write-Log ''
    Write-Log "[DRY-RUN] Would mount $WimPath (index $Index) at $MountPath"
    foreach ($cab in $CabFiles) {
        Write-Log "[DRY-RUN] Would run: Add-WindowsPackage -Path $MountPath -PackagePath $($cab.FullName)"
    }
    if ($SetAsDefault) {
        Write-Log "[DRY-RUN] Would run: dism.exe /Image:$MountPath /Set-SKUIntlDefaults:$LanguageTag"
    }
    Write-Log "[DRY-RUN] Would dismount $MountPath -Save"
    Write-Log ''
    Write-Log '========== 13 dry-run complete =========='
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
    foreach ($cab in $CabFiles) {
        Write-Log "Injecting $($cab.Name)..."
        Add-WindowsPackage -Path $MountPath -PackagePath $cab.FullName -ErrorAction Stop | Out-Null
        Write-Log "  Injected $($cab.Name)" 'OK'
    }

    if ($SetAsDefault) {
        Write-Log "Setting $LanguageTag as image default (Set-SKUIntlDefaults)..."
        $DismOut = & dism.exe /Image:$MountPath /Set-SKUIntlDefaults:$LanguageTag 2>&1
        $DismOut | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "dism /Set-SKUIntlDefaults exited $LASTEXITCODE" }
        Write-Log "$LanguageTag set as image default" 'OK'
    }
} catch {
    Write-Log "Language pack injection failed: $_" 'ERROR'
    Write-Log 'Continuing to dismount -Discard so the mount point is not left stuck.' 'WARN'
    $StepFailed = $true
}

Write-Log ''
if ($StepFailed) {
    Write-Log 'Dismounting WITHOUT saving (injection failed)...'
    try {
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop | Out-Null
        Write-Log 'Dismounted (discarded).' 'WARN'
    } catch {
        Write-Log "Dismount -Discard also failed: $_" 'ERROR'
        Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Discard, or Clear-WindowsCorruptMountPoint" 'ERROR'
    }
    Write-Log '========== 13 FAILED =========='
    exit 1
}

Write-Log 'Dismounting and saving (this can take several minutes)...'
try {
    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
    Write-Log 'Dismount complete - language pack(s) committed to install.wim' 'OK'
} catch {
    Write-Log "Dismount -Save failed: $_" 'ERROR'
    Write-Log "Manual recovery: Dismount-WindowsImage -Path '$MountPath' -Save, or Clear-WindowsCorruptMountPoint" 'ERROR'
    exit 1
}

Write-Log ''
Write-Log '========== 13 complete =========='
Write-Log 'Next: run 10-Build-OemLayer.ps1' 'NEXT'
