#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Build $OEM$ Folder Structure (v2.4)

.DESCRIPTION
    Builds the sources\$OEM$\ folder tree that Windows Setup processes
    automatically during installation. Includes:

      - Drivers from Drivers-SCCM\ (full tree, all file types)
      - Branding files (wallpaper, lock screen) to C:\Windows\Web\Wallpaper\CompanyBrand\
      - SetupComplete.cmd to C:\Windows\Setup\Scripts\
      - CMTrace.exe to C:\Windows\System32\
      - OEMLogo.bmp: RETIRED in v2.4 (Win11 Settings does not render it)
      - AuditMode\ folder to C:\AuditMode\

    $OEM$ folder mapping (Microsoft convention):
      $OEM$\$$\          -> C:\Windows\
      $OEM$\$1\          -> C:\ (system drive root)
      $OEM$\$$\System32  -> C:\Windows\System32\
      $OEM$\$$\Setup\Scripts -> C:\Windows\Setup\Scripts\

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.NOTES
    Document: WIN11-GOLDIMG-001 v2.4
    Runs AFTER script 09 (Dismount) - operates on the extracted ISO tree,
    NOT on the mounted WIM.

    Changes from v2.3:
      - WIM mount check narrowed to E:\WimMount only (no longer trips on
        MDT or other unrelated WIM mounts elsewhere on the build server)
      - Driver staging copies ALL contents of Drivers-SCCM\ (not .inf-only).
        Restores v2.2.1 behaviour. PnP at DevicePath time will handle
        whatever .inf trees exist; non-driver files (.exe, .cab) are
        harmless passengers.
      - AuditMode\ folder copied to $OEM$\$1\AuditMode (Apply-SecurityBaseline
        and Apply-PostInstallCustomization)
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$MountPath,
    [string]$IsoExtractDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
# BuildRoot is the actual folder this repo lives in - NOT a hardcoded 'E:\Build'.
# That hardcoded value broke on any checkout that isn't literally at E:\Build
# (e.g. E:\Modern-Windows-Image-Factory) - BrandingSrc/OEMTemplateSrc/DriversSrc
# below would silently point at a folder that doesn't exist.
$BuildRoot     = Split-Path -Parent $PSScriptRoot
$Config        = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $IsoExtractDir) { $IsoExtractDir = $Config.ExtractDest }
$ISOExtractDir = $IsoExtractDir
$OEMRoot       = Join-Path $ISOExtractDir 'sources\$OEM$'

$BrandingSrc    = Join-Path $BuildRoot 'Branding'
$OEMTemplateSrc = Join-Path $BuildRoot 'OEM-Template'
$DriversSrc     = Join-Path $BuildRoot 'Drivers-SCCM'
$AuditModeSrc   = Join-Path $BuildRoot 'AuditMode'
# LGPO/ and SCT/ are top-level repo folders (siblings of AuditMode/, not
# nested inside it - see root README.md folder structure). Staged into
# $OEM$\$1\AuditMode\LGPO and \SCT (v2.6) so AuditMode\Apply-SecurityBaseline.ps1
# finds them at its default -LgpoPath/-MachineBaselinePath on the reference
# VM without the operator having to hand-copy them post-install.
$LgpoSrc        = Join-Path $BuildRoot 'LGPO'
$SctSrc         = Join-Path $BuildRoot 'SCT'

$WallpaperFile   = 'Wallpaper.jpg'
$LockScreenFile  = 'LockScreen.jpg'
$BrandingDestRel = 'Web\Wallpaper\CompanyBrand'   # under C:\Windows\

if (-not $MountPath) { $MountPath = $Config.MountPath }
$LocalWimMount = $MountPath

$LogDir    = Join-Path $BuildRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "10-BuildOemLayer-$Mode-$Timestamp.log"

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

Write-Log '========== 10 - Build OEM Folder Structure (v2.4) =========='
Write-Log "Mode:           $Mode"
Write-Log "ISO extract:    $ISOExtractDir"
Write-Log "OEM root:       $OEMRoot"
Write-Log "Branding src:   $BrandingSrc"
Write-Log "OEM-Template:   $OEMTemplateSrc"
Write-Log "Drivers src:    $DriversSrc"
Write-Log "AuditMode src:  $AuditModeSrc"

# --- Pre-flight ---
if (-not (Test-Path $ISOExtractDir)) {
    Write-Log "ISO extract dir not found: $ISOExtractDir" 'ERROR'
    Write-Log 'Run script 02 (ExtractISO) first.' 'ERROR'
    exit 1
}

# Check ONLY E:\WimMount, not all mounts globally
# (avoids tripping on MDT, other tools, or stale mounts elsewhere)
try {
    $LocalMount = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                  Where-Object { $_.Path -eq $LocalWimMount }
    if ($LocalMount) {
        Write-Log "WIM is still mounted at $LocalWimMount" 'ERROR'
        Write-Log 'Script 10 runs AFTER 09-Dismount-Image. Run 09 first.' 'ERROR'
        exit 1
    }
    Write-Log "No WIM mounted at $LocalWimMount (expected at this stage)" 'OK'

    # Informational only - log other mounts but do not block
    $OtherMounts = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                   Where-Object { $_.Path -ne $LocalWimMount }
    if ($OtherMounts) {
        Write-Log 'NOTE: Other WIM mounts exist on this machine (unrelated to this build):'
        foreach ($m in $OtherMounts) {
            Write-Log "  $($m.Path)"
        }
        Write-Log 'These are ignored. Build continues.'
    }
} catch {
    Write-Log "Mount check failed: $_" 'WARN'
    Write-Log 'Continuing - mount check is informational only at this stage'
}

# --- Build $OEM$ subtree paths ---
$Path_OEM_System32     = Join-Path $OEMRoot '$$\System32'
$Path_OEM_SetupScripts = Join-Path $OEMRoot '$$\Setup\Scripts'
$Path_OEM_Branding     = Join-Path $OEMRoot "`$`$\$BrandingDestRel"
$Path_OEM_Drivers      = Join-Path $OEMRoot '$1\Drivers'
$Path_OEM_AuditMode    = Join-Path $OEMRoot '$1\AuditMode'
$Path_OEM_AuditModeLgpo = Join-Path $Path_OEM_AuditMode 'LGPO'
$Path_OEM_AuditModeSct  = Join-Path $Path_OEM_AuditMode 'SCT'

# ==========================================================================
# STEP 1 - Create $OEM$ skeleton
# ==========================================================================
Write-Log ''
Write-Log '----- Step 1: Create $OEM$ skeleton -----'

$Folders = @(
    $OEMRoot,
    $Path_OEM_System32,
    $Path_OEM_SetupScripts,
    $Path_OEM_Branding,
    $Path_OEM_Drivers,
    $Path_OEM_AuditMode
)
foreach ($f in $Folders) {
    if (Test-Path $f) {
        Write-Log "Exists: $f"
    } else {
        if ($Apply) {
            New-Item -Path $f -ItemType Directory -Force | Out-Null
            Write-Log "Created: $f" 'OK'
        } else {
            Write-Log "[DRY-RUN] Would create: $f"
        }
    }
}

# ==========================================================================
# STEP 2 - SetupComplete.cmd -> $OEM$\$$\Setup\Scripts\
# ==========================================================================
Write-Log ''
Write-Log '----- Step 2: SetupComplete.cmd -----'

$SetupCompleteSrc  = Join-Path $OEMTemplateSrc 'SetupComplete.cmd'
$SetupCompleteDest = Join-Path $Path_OEM_SetupScripts 'SetupComplete.cmd'

if (-not (Test-Path $SetupCompleteSrc)) {
    Write-Log "SetupComplete.cmd not found at: $SetupCompleteSrc" 'ERROR'
    Write-Log 'Place SetupComplete.cmd in OEM-Template\ before running this script.' 'ERROR'
    exit 1
}

# Reject smart quotes / em-dashes (lesson learned from v2.1.5 docx round-trip)
$Content = Get-Content -Path $SetupCompleteSrc -Raw -Encoding UTF8
$BadChars = @([char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019, [char]0x2014, [char]0x2013)
$BadNames = @('left-double-quote','right-double-quote','left-single-quote','right-single-quote','em-dash','en-dash')
$Found = @()
for ($i = 0; $i -lt $BadChars.Count; $i++) {
    if ($Content.IndexOf($BadChars[$i]) -ge 0) { $Found += $BadNames[$i] }
}
if ($Found.Count -gt 0) {
    Write-Log "SetupComplete.cmd contains non-ASCII chars: $($Found -join ', ')" 'ERROR'
    Write-Log 'Re-save the file as ASCII before continuing (do not edit in Word).' 'ERROR'
    exit 1
}
Write-Log 'SetupComplete.cmd passes ASCII-only validation' 'OK'

if ($Apply) {
    Copy-Item -Path $SetupCompleteSrc -Destination $SetupCompleteDest -Force
    Write-Log "Copied: $SetupCompleteSrc -> $SetupCompleteDest" 'OK'
} else {
    Write-Log "[DRY-RUN] Would copy: $SetupCompleteSrc -> $SetupCompleteDest"
}

# ==========================================================================
# STEP 3 - CMTrace.exe -> $OEM$\$$\System32\
# ==========================================================================
Write-Log ''
Write-Log '----- Step 3: CMTrace.exe -----'

$CMTraceSrc  = Join-Path $OEMTemplateSrc 'CMTrace.exe'
$CMTraceDest = Join-Path $Path_OEM_System32 'CMTrace.exe'

if (-not (Test-Path $CMTraceSrc)) {
    Write-Log "CMTrace.exe not found at: $CMTraceSrc" 'WARN'
    Write-Log 'CMTrace will NOT be staged. SetupComplete.cmd will skip CMTrace registration at runtime.' 'WARN'
} else {
    if ($Apply) {
        Copy-Item -Path $CMTraceSrc -Destination $CMTraceDest -Force
        Write-Log "Copied: $CMTraceSrc -> $CMTraceDest" 'OK'
    } else {
        Write-Log "[DRY-RUN] Would copy: $CMTraceSrc -> $CMTraceDest"
    }
}

# ==========================================================================
# STEP 4 - OEMLogo.bmp -> RETIRED in v2.4
# ==========================================================================
# Win11 Settings > About does NOT reliably render the legacy
# OEMInformation\Logo bitmap. It was confirmed not to appear on the
# deployed reference build. The logo is therefore retired: it is no longer
# staged, and SetupComplete.cmd actively deletes any stale Logo value.
# OEM Information TEXT fields (Manufacturer, Model, Support*) are retained.
Write-Log ''
Write-Log '----- Step 4: OEMLogo.bmp (RETIRED in v2.4 - not staged) -----'
Write-Log 'OEMLogo retired: Win11 Settings does not render it. OEM text fields retained.' 'INFO'

# ==========================================================================
# STEP 5 - Branding files (wallpaper + lock screen)
# ==========================================================================
Write-Log ''
Write-Log '----- Step 5: Branding files -----'

$WallpaperSrc  = Join-Path $BrandingSrc $WallpaperFile
$LockScreenSrc = Join-Path $BrandingSrc $LockScreenFile

foreach ($pair in @(
    @{ Src = $WallpaperSrc;  Name = 'Wallpaper'   },
    @{ Src = $LockScreenSrc; Name = 'Lock screen' }
)) {
    if (-not (Test-Path $pair.Src)) {
        Write-Log "$($pair.Name) source missing: $($pair.Src)" 'ERROR'
        Write-Log "SetupComplete.cmd will log an ERROR at runtime if this file isn't present." 'ERROR'
        continue
    }

    $DestFile = Join-Path $Path_OEM_Branding (Split-Path $pair.Src -Leaf)
    if ($Apply) {
        Copy-Item -Path $pair.Src -Destination $DestFile -Force
        attrib -R $DestFile
        Write-Log "Copied $($pair.Name): $($pair.Src) -> $DestFile" 'OK'
    } else {
        Write-Log "[DRY-RUN] Would copy $($pair.Name): $($pair.Src) -> $DestFile"
    }
}

# ==========================================================================
# STEP 6 - Drivers tree (FULL copy - all file types)
# ==========================================================================
Write-Log ''
Write-Log '----- Step 6: Drivers (full tree copy) -----'

if (-not (Test-Path $DriversSrc)) {
    Write-Log "Drivers source dir not present: $DriversSrc" 'WARN'
    Write-Log 'No drivers will be staged. PnP will rely on inbox drivers only.' 'WARN'
} else {
    $DriverContent = Get-ChildItem -Path $DriversSrc -Recurse -ErrorAction SilentlyContinue
    if (-not $DriverContent -or $DriverContent.Count -eq 0) {
        Write-Log "Drivers source folder exists but is EMPTY: $DriversSrc" 'WARN'
        Write-Log 'Place driver content under Drivers-SCCM\ before running 06.' 'WARN'
    } else {
        $TotalSize = ($DriverContent | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
        $TotalSizeGB = if ($TotalSize) { [math]::Round($TotalSize / 1GB, 2) } else { 0 }
        $InfCount = ($DriverContent | Where-Object { $_.Extension -eq '.inf' } | Measure-Object).Count
        $FileCount = ($DriverContent | Where-Object { -not $_.PSIsContainer } | Measure-Object).Count

        Write-Log "Drivers source summary:"
        Write-Log "  Total files: $FileCount"
        Write-Log "  Total size:  $TotalSizeGB GB"
        Write-Log "  .inf files:  $InfCount"

        if ($InfCount -eq 0) {
            Write-Log 'WARN - No .inf files in driver tree.' 'WARN'
            Write-Log 'WARN - DevicePath / pnputil binds drivers via .inf only. Drivers will be copied' 'WARN'
            Write-Log 'WARN - to C:\Drivers but NOT bound by PnP. They may be packed .exe / .cab / .msi.' 'WARN'
            Write-Log 'WARN - Extract them to .inf trees before next build cycle. See C7 in PROJECT-GOALS.' 'WARN'
        }

        if ($Apply) {
            $RoboLog = Join-Path $LogDir "robocopy-drivers-$Timestamp.log"
            Write-Log "Robocopying $DriversSrc -> $Path_OEM_Drivers (log: $RoboLog)"

            # /MIR mirrors the entire tree; /R:1 /W:1 fast-fail; /NFL /NDL /NP quiet output
            & robocopy.exe $DriversSrc $Path_OEM_Drivers /MIR /R:1 /W:1 /NFL /NDL /NP /LOG:$RoboLog | Out-Null
            $RoboCode = $LASTEXITCODE

            # robocopy exit codes: 0 = no copy needed, 1 = files copied OK, 2 = extra files,
            # 4 = mismatched, 8+ = errors. <8 is success.
            if ($RoboCode -lt 8) {
                Write-Log "Driver copy completed (robocopy exit $RoboCode = success)" 'OK'

                # Verify destination actually has content
                $CopiedFiles = (Get-ChildItem -Path $Path_OEM_Drivers -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                $CopiedSize  = (Get-ChildItem -Path $Path_OEM_Drivers -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $CopiedSizeGB = if ($CopiedSize) { [math]::Round($CopiedSize / 1GB, 2) } else { 0 }
                Write-Log "  Destination has $CopiedFiles files, $CopiedSizeGB GB"

                if ($CopiedFiles -eq 0) {
                    Write-Log 'WARN - Destination is empty despite robocopy success. Check source permissions.' 'WARN'
                }
            } else {
                Write-Log "robocopy exit code $RoboCode (>= 8 = error). Check $RoboLog" 'ERROR'
            }
        } else {
            Write-Log "[DRY-RUN] Would robocopy $DriversSrc -> $Path_OEM_Drivers (full tree, all file types)"
        }
    }
}

# ==========================================================================
# STEP 7 - AuditMode folder -> $OEM$\$1\AuditMode\
# ==========================================================================
Write-Log ''
Write-Log '----- Step 7: AuditMode scripts -----'

if (-not (Test-Path $AuditModeSrc)) {
    Write-Log "AuditMode source folder not present: $AuditModeSrc" 'WARN'
    Write-Log 'Apply-SecurityBaseline.ps1 will NOT be available on the reference VM.' 'WARN'
} else {
    if ($Apply) {
        $RoboLog = Join-Path $LogDir "robocopy-auditmode-$Timestamp.log"
        & robocopy.exe $AuditModeSrc $Path_OEM_AuditMode /MIR /R:1 /W:1 /NFL /NDL /NP /LOG:$RoboLog | Out-Null
        $RoboCode = $LASTEXITCODE
        if ($RoboCode -lt 8) {
            Write-Log "AuditMode folder staged (robocopy exit $RoboCode)" 'OK'
            $AuditFiles = (Get-ChildItem -Path $Path_OEM_AuditMode -Recurse -File | Measure-Object).Count
            Write-Log "  Destination has $AuditFiles files"
        } else {
            Write-Log "AuditMode robocopy exit code $RoboCode. Check $RoboLog" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would robocopy $AuditModeSrc -> $Path_OEM_AuditMode"
    }
}

# ==========================================================================
# STEP 7b - LGPO\ and SCT\ -> $OEM$\$1\AuditMode\LGPO, \SCT (v2.6)
# ==========================================================================
Write-Log ''
Write-Log '----- Step 7b: LGPO / SCT baseline (for Apply-SecurityBaseline.ps1) -----'

foreach ($pair in @(
    @{ Src = $LgpoSrc; Dest = $Path_OEM_AuditModeLgpo; Name = 'LGPO' },
    @{ Src = $SctSrc;  Dest = $Path_OEM_AuditModeSct;  Name = 'SCT'  }
)) {
    if (-not (Test-Path $pair.Src)) {
        Write-Log "$($pair.Name) source folder not present: $($pair.Src) - see $($pair.Name)/README.md" 'WARN'
        continue
    }
    $Content = Get-ChildItem -Path $pair.Src -Recurse -ErrorAction SilentlyContinue
    if (-not $Content -or $Content.Count -eq 0) {
        Write-Log "$($pair.Name) source folder exists but is EMPTY: $($pair.Src) - see $($pair.Name)/README.md" 'WARN'
        continue
    }
    if ($Apply) {
        $RoboLog = Join-Path $LogDir "robocopy-$($pair.Name.ToLower())-$Timestamp.log"
        & robocopy.exe $pair.Src $pair.Dest /MIR /R:1 /W:1 /NFL /NDL /NP /LOG:$RoboLog | Out-Null
        $RoboCode = $LASTEXITCODE
        if ($RoboCode -lt 8) {
            Write-Log "$($pair.Name) staged (robocopy exit $RoboCode)" 'OK'
        } else {
            Write-Log "$($pair.Name) robocopy exit code $RoboCode. Check $RoboLog" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would robocopy $($pair.Src) -> $($pair.Dest)"
    }
}

# ==========================================================================
# STEP 8 - Final sanity check of $OEM$ tree
# ==========================================================================
Write-Log ''
Write-Log '----- Step 8: Final $OEM$ verification -----'

if ($Apply) {
    $ExpectedFiles = @(
        $SetupCompleteDest,
        (Join-Path $Path_OEM_Branding $WallpaperFile),
        (Join-Path $Path_OEM_Branding $LockScreenFile)
    )
    if (Test-Path $CMTraceSrc) { $ExpectedFiles += $CMTraceDest }
    # OEMLogo retired in v2.4 - no longer expected in the $OEM$ tree

    foreach ($f in $ExpectedFiles) {
        if (Test-Path $f) {
            Write-Log "  [OK]   $f"
        } else {
            Write-Log "  [MISS] $f" 'ERROR'
        }
    }

    # Total size of $OEM$ tree
    $TotalSize = (Get-ChildItem -Path $OEMRoot -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
    $TotalSizeMB = if ($TotalSize) { [math]::Round($TotalSize / 1MB, 2) } else { 0 }
    $TotalCount = (Get-ChildItem -Path $OEMRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Log ''
    Write-Log "Total `$OEM`$ tree: $TotalCount files, $TotalSizeMB MB"
}

Write-Log ''
Write-Log '========== 10 complete =========='
if (-not $Apply) {
    Write-Log ''
    Write-Log '*** DRY-RUN. Re-run with -Apply to execute. ***' 'WARN'
}
Write-Log "Next: run 11-Build-Iso.ps1" 'NEXT'
