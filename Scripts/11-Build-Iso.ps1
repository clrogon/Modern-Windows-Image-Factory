#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Rebuild bootable UEFI ISO (v2.3.2)

.DESCRIPTION
    Repackages the extracted ISO tree back into a bootable UEFI/BIOS
    dual-boot ISO using oscdimg.exe from the Windows ADK.

    Also stages Autounattend.xml at the ISO root if present.

    Produces:
      - E:\ISO\Win11_25H2_Custom_<date>.iso
      - E:\ISO\Win11_25H2_Custom_<date>.iso.manifest.txt (SHA256)

.PARAMETER Apply
    Default $false (dry-run). Pass -Apply to execute.

.NOTES
    Document: WIN11-GOLDIMG-001 v2.3.2

    Changes from v2.3.1:
      - oscdimg invoked via cmd.exe /c to isolate stderr from PowerShell's
        $ErrorActionPreference = 'Stop'. oscdimg writes its progress bar
        to stderr; PowerShell treats stderr as ErrorRecord and throws a
        RemoteException, killing oscdimg before it finishes. cmd.exe /c
        lets oscdimg run to completion.
      - oscdimg stdout+stderr captured to a dedicated log file for diagnosis.
      - $LASTEXITCODE checked AFTER oscdimg finishes, not during piping.
#>

[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$Win11Version  = '25H2'
$ISOExtractDir = "E:\ISO\Win11_${Win11Version}_7"
$BuildRoot     = 'E:\Build'
$ISOOutputDir  = 'E:\ISO'
$OEMTemplateSrc = Join-Path $BuildRoot 'OEM-Template'

# ADK path on the ORG build server (non-standard)
$ADKPath = 'E:\Windows assessment and deployed kit\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
$Oscdimg = Join-Path $ADKPath 'oscdimg.exe'

$ISOLabel  = "WIN11_${Win11Version}"
$ISODate   = Get-Date -Format 'yyyyMMdd'
$ISOOutput = Join-Path $ISOOutputDir "Win11_${Win11Version}_Custom_$ISODate.iso"

$LogDir    = Join-Path $BuildRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogDir "BuildIso-$Mode-$Timestamp.log"

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

Write-Log '========== 07 - Rebuild ISO (v2.3.2) =========='
Write-Log "Mode:           $Mode"
Write-Log "ISO extract:    $ISOExtractDir"
Write-Log "Output ISO:     $ISOOutput"
Write-Log "ADK oscdimg:    $Oscdimg"

# ==========================================================================
# Pre-flight
# ==========================================================================
if (-not (Test-Path $Oscdimg)) {
    Write-Log "oscdimg.exe not found at: $Oscdimg" 'ERROR'
    Write-Log 'Edit $ADKPath at the top of this script to point at your ADK install.' 'ERROR'
    exit 1
}
Write-Log 'oscdimg.exe found' 'OK'

if (-not (Test-Path $ISOExtractDir)) {
    Write-Log "ISO extract dir not found: $ISOExtractDir" 'ERROR'
    exit 1
}

$InstallWim = Join-Path $ISOExtractDir 'sources\install.wim'
if (-not (Test-Path $InstallWim)) {
    Write-Log "install.wim not found: $InstallWim" 'ERROR'
    Write-Log 'Run scripts 01-05 first.' 'ERROR'
    exit 1
}
$WimSize = (Get-Item $InstallWim).Length
$WimSizeGB = [math]::Round($WimSize / 1GB, 2)
Write-Log "install.wim found: $WimSizeGB GB" 'OK'

# Check OEM folder exists
$OEMRoot = Join-Path $ISOExtractDir 'sources\$OEM$'
if (Test-Path $OEMRoot) {
    $OEMFiles = (Get-ChildItem -Path $OEMRoot -Recurse -File | Measure-Object).Count
    $OEMSize = (Get-ChildItem -Path $OEMRoot -Recurse -File | Measure-Object Length -Sum).Sum
    $OEMSizeMB = if ($OEMSize) { [math]::Round($OEMSize / 1MB, 2) } else { 0 }
    Write-Log "OEM tree: $OEMFiles files, $OEMSizeMB MB" 'OK'
} else {
    Write-Log "OEM folder not present at $OEMRoot. Run 06 first." 'WARN'
}

# Check available disk space
$Drive = (Get-Item $ISOOutputDir).PSDrive
$FreeSpaceGB = [math]::Round($Drive.Free / 1GB, 2)
$EstimatedISOSizeGB = [math]::Round(($WimSize + $OEMSize + 500MB) / 1GB, 2)
Write-Log "Estimated ISO size: $EstimatedISOSizeGB GB"
Write-Log "Free space on $($Drive.Name): $FreeSpaceGB GB"
if ($FreeSpaceGB -lt ($EstimatedISOSizeGB + 2)) {
    Write-Log "Free space may be insufficient. Need ~$EstimatedISOSizeGB GB + headroom." 'WARN'
}

# ==========================================================================
# Autounattend.xml -> ISO root
# ==========================================================================
$AutounattendSrc  = Join-Path $OEMTemplateSrc 'Autounattend.xml'
$AutounattendDest = Join-Path $ISOExtractDir 'Autounattend.xml'

Write-Log ''
Write-Log '----- Autounattend.xml at ISO root -----'

if (-not (Test-Path $AutounattendSrc)) {
    Write-Log "No Autounattend.xml at $AutounattendSrc - skipping" 'INFO'
    Write-Log 'ISO will boot to interactive install prompts.'
} else {
    # Validate XML well-formedness
    try {
        [xml]$Doc = Get-Content -Path $AutounattendSrc -Raw -Encoding UTF8
        $PassCount = $Doc.unattend.settings.Count
        $Passes = ($Doc.unattend.settings | ForEach-Object { $_.pass }) -join ', '
        Write-Log "Autounattend.xml is well-formed. Passes: $Passes ($PassCount total)" 'OK'
    } catch {
        Write-Log "Autounattend.xml is malformed: $_" 'ERROR'
        Write-Log 'Fix the XML or remove it from OEM-Template\ before re-running.' 'ERROR'
        throw 'Autounattend.xml validation failed'
    }

    # Check for the shipped default/placeholder password (safety net).
    # Must match the actual placeholder in OEM-Template\Autounattend.xml (see its
    # header comment and the root README's placeholder table) - not a made-up string.
    $XmlText = Get-Content -Path $AutounattendSrc -Raw
    $DefaultPasswordPlaceholders = @('!ChangeMe2026!', 'REPLACE_WITH_EPHEMERAL_PWD')
    foreach ($placeholder in $DefaultPasswordPlaceholders) {
        if ($XmlText -match [regex]::Escape($placeholder)) {
            Write-Log "Autounattend.xml still contains the default placeholder password ($placeholder)" 'ERROR'
            Write-Log 'Substitute a real ephemeral password before building.' 'ERROR'
            exit 1
        }
    }

    # Detect overlap with SetupComplete.cmd (informational only)
    $Overlaps = @()
    if ($XmlText -match '<TimeZone>')     { $Overlaps += 'TimeZone' }
    if ($XmlText -match '<UserLocale>')   { $Overlaps += 'UserLocale' }
    if ($XmlText -match '<UILanguage>')   { $Overlaps += 'UILanguage' }
    if ($XmlText -match '<InputLocale>')  { $Overlaps += 'InputLocale' }
    if ($XmlText -match '<SystemLocale>') { $Overlaps += 'SystemLocale' }

    if ($Overlaps.Count -gt 0) {
        Write-Log "Autounattend.xml sets: $($Overlaps -join ', ')" 'WARN'
        Write-Log 'SetupComplete.cmd Tasks 2/6/7 also set these - SetupComplete wins.' 'WARN'
    }

    if ($XmlText -match '<AutoLogon>') {
        Write-Log 'Autounattend.xml configures AutoLogon (plain-text password). Acceptable for audit-mode reference VM only.' 'WARN'
    }

    if ($Apply) {
        Copy-Item -Path $AutounattendSrc -Destination $AutounattendDest -Force
        attrib -R $AutounattendDest
        Write-Log "Copied: $AutounattendSrc -> $AutounattendDest" 'OK'
    } else {
        Write-Log "[DRY-RUN] Would copy: $AutounattendSrc -> $AutounattendDest"
    }
}

# ==========================================================================
# Build the ISO with oscdimg
# ==========================================================================
Write-Log ''
Write-Log '----- oscdimg ISO build -----'

# UEFI + BIOS dual boot files
$EtfsBoot = Join-Path $ISOExtractDir 'boot\etfsboot.com'
$EfiBoot  = Join-Path $ISOExtractDir 'efi\microsoft\boot\efisys.bin'

if (-not (Test-Path $EtfsBoot)) { Write-Log "etfsboot.com missing: $EtfsBoot" 'ERROR'; exit 1 }
if (-not (Test-Path $EfiBoot))  { Write-Log "efisys.bin missing: $EfiBoot" 'ERROR'; exit 1 }

# Build oscdimg argument string
# NOTE: -h includes hidden files; -m ignores max size; -u2 UDF; -o optimize
$BootData = "2#p0,e,b`"$EtfsBoot`"#pEF,e,b`"$EfiBoot`""
$OscdimgArgString = "-m -o -h -u2 -udfver102 -l$ISOLabel -bootdata:$BootData `"$ISOExtractDir`" `"$ISOOutput`""

if (Test-Path $ISOOutput) {
    Write-Log "Output ISO exists, will be overwritten: $ISOOutput" 'WARN'
    if ($Apply) { Remove-Item $ISOOutput -Force }
}

Write-Log "oscdimg command:"
Write-Log "  `"$Oscdimg`" $OscdimgArgString"

if ($Apply) {
    $StartTime = Get-Date

    # =====================================================================
    # CRITICAL: invoke oscdimg via cmd.exe /c to isolate its stderr from
    # PowerShell's $ErrorActionPreference = 'Stop'.
    #
    # oscdimg writes its progress bar to stderr, which is normal CLI
    # behaviour. PowerShell converts stderr output into ErrorRecord objects.
    # With $ErrorActionPreference = 'Stop', the FIRST stderr write triggers
    # a RemoteException and kills oscdimg immediately.
    #
    # cmd.exe /c lets oscdimg run to completion. We capture all output
    # (stdout + stderr) to a log file and check $LASTEXITCODE after.
    # =====================================================================
    $OscdimgLog = Join-Path $LogDir "oscdimg-output-$Timestamp.log"
    $CmdLine = "`"$Oscdimg`" $OscdimgArgString"

    Write-Log "oscdimg output captured to: $OscdimgLog"
    Write-Log 'Running oscdimg (this can take several minutes for a large image)...'

    # cmd /c runs the native command, >file 2>&1 captures both stdout and stderr
    cmd.exe /c "$CmdLine > `"$OscdimgLog`" 2>&1"

    $OscdimgExit = $LASTEXITCODE
    $Duration = (Get-Date) - $StartTime

    # Log the oscdimg output for the audit trail
    if (Test-Path $OscdimgLog) {
        $OscdimgOutput = Get-Content -Path $OscdimgLog -Raw -ErrorAction SilentlyContinue
        Write-Log 'oscdimg output:'
        ($OscdimgOutput -split "`n") | ForEach-Object { Write-Log "  $_" }
    }

    if ($OscdimgExit -ne 0) {
        Write-Log "oscdimg exited with code $OscdimgExit" 'ERROR'
        Write-Log "Check $OscdimgLog for details." 'ERROR'
        exit 1
    }

    Write-Log "oscdimg completed in $([math]::Round($Duration.TotalMinutes, 2)) minutes (exit code 0)" 'OK'

    # Sanity check ISO was created and is plausible size
    if (-not (Test-Path $ISOOutput)) {
        Write-Log "Output ISO was not created: $ISOOutput" 'ERROR'
        exit 1
    }
    $ISOSize = (Get-Item $ISOOutput).Length
    $ISOSizeGB = [math]::Round($ISOSize / 1GB, 2)
    Write-Log "Output ISO size: $ISOSizeGB GB"

    if ($ISOSize -lt 4GB) {
        Write-Log "Output ISO is smaller than 4 GB - likely missing content. Verify before deployment." 'WARN'
    } else {
        Write-Log 'ISO size looks plausible' 'OK'
    }

    # Confirm Autounattend.xml made it in
    if (Test-Path $AutounattendDest) {
        Write-Log "Confirmed Autounattend.xml present at ISO root path: $AutounattendDest" 'OK'
    } else {
        Write-Log "Autounattend.xml NOT at ISO root - install will be interactive" 'WARN'
    }

} else {
    Write-Log '[DRY-RUN] Would run oscdimg with above arguments'
}

# ==========================================================================
# SHA256 manifest
# ==========================================================================
Write-Log ''
Write-Log '----- SHA256 manifest -----'

if ($Apply -and (Test-Path $ISOOutput)) {
    $ManifestPath = "$ISOOutput.manifest.txt"
    try {
        Write-Log 'Calculating SHA256 (this can take a few minutes for a large ISO)...'
        $Hash = Get-FileHash -Path $ISOOutput -Algorithm SHA256

        $ManifestContent = @"
Windows 11 Image Builder - ISO Manifest
========================================
Document    : WIN11-GOLDIMG-001 v2.3.2
Built       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Build host  : $env:COMPUTERNAME
Built by    : $env:USERNAME
ISO file    : $(Split-Path $ISOOutput -Leaf)
ISO size    : $ISOSizeGB GB
SHA256      : $($Hash.Hash)

Verify on receiving end:
   Get-FileHash -Algorithm SHA256 -Path <iso>
   Compare to value above.
"@
        $ManifestContent | Out-File -FilePath $ManifestPath -Encoding UTF8 -Force
        Write-Log "Manifest written: $ManifestPath" 'OK'
        Write-Log "SHA256: $($Hash.Hash)"
    } catch {
        Write-Log "SHA256 manifest generation failed: $_" 'ERROR'
    }
} elseif (-not $Apply) {
    Write-Log '[DRY-RUN] Would generate SHA256 manifest after ISO build'
}

Write-Log ''
Write-Log '========== 07 complete =========='
if (-not $Apply) {
    Write-Log ''
    Write-Log '*** DRY-RUN. Re-run with -Apply to execute. ***' 'WARN'
} else {
    Write-Log ''
    Write-Log "*** ISO ready at: $ISOOutput ***" 'OK'
    Write-Log "*** Manifest:     $ISOOutput.manifest.txt ***" 'OK'
}
Write-Log ''
Write-Log 'Build-server pipeline (01-11) complete. Next phase = reference VM, audit mode:' 'NEXT'
Write-Log '  1. Install Windows from this ISO on the reference VM (boots to audit mode).' 'NEXT'
Write-Log '  2. cd C:\AuditMode ; .\Apply-SecurityBaseline.ps1 -Apply $true  (reboot, then -VerifyOnly).' 'NEXT'
Write-Log '  3a. THIN  image: no software baked - go straight to Sysprep + capture.' 'NEXT'
Write-Log '  3b. THICK image: cd C:\AuditMode\Software ; .\Install-ImageSoftware.ps1 -ImageProfile Thick ; then Sysprep + capture.' 'NEXT'
