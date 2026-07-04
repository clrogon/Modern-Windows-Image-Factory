#Requires -Version 5.1
<#
.SYNOPSIS
    ORG - Office (M365 Apps) source pre-download for the THICK image.
    Runs ODT setup.exe /download to fetch the Semi-Annual source ONCE, on a
    machine WITH internet (build server / staging workstation - NOT the audit VM).

.DESCRIPTION
    Why pre-download:
      - The ODT config sets AllowCdnFallback=FALSE, so the install in audit mode
        has no internet fallback - the source MUST be local.
      - Downloading once and reusing gives deterministic, reproducible builds
        (a fresh /download each build would pull whatever channel build is current
        that day).
      - The reference VM stays offline (no domain, no internet) during the build.

    Flow:
      1. The helper defaults to its own folder ($PSScriptRoot = E:\Build\AuditMode\Software\ODT).
      2. Run this script (-Apply) on a machine with internet -> writes the source to
         <OdtRoot>\Office\Data\<build> and records the build in STAGED-OFFICE-VERSION.txt.
      3. Run 10-Build-OemLayer.ps1 + 11-Build-Iso.ps1 to pack everything into the ISO.
      4. The ISO installs on the reference VM; Office source lands at C:\AuditMode\Software\ODT\
         automatically. Install-ImageSoftware.ps1 runs setup.exe /configure (offline).

    REVIEW: re-run this roughly every 6 months (SAEC feature updates land ~Jan / ~Jul)
    to refresh the source, and re-verify the Adobe Acrobat build at the same time.

.PARAMETER OdtRoot
    Folder holding setup.exe and the ODT config (and where Office\ is created).
    Defaults to the script's own folder ($PSScriptRoot = the ODT subfolder in the build tree).

.PARAMETER ConfigXml
    ODT config file name inside OdtRoot. Default: ODT_SemiAnnual.xml

.PARAMETER Apply
    Execute the download. Default is a dry run (shows the command, validates paths).

.EXAMPLE
    .\Download-OfficeSource.ps1                 # dry run
    .\Download-OfficeSource.ps1 -Apply $true    # download the source

.NOTES
    Author  : Your Name - IT Solutions Architecture / Solutions Architecture
    Version : 1.0 | 2026-06-03
    PS      : 5.1. ASCII only. Dry-run default (project convention G11/D-006).
#>

[CmdletBinding()]
param(
    [string]$OdtRoot   = $PSScriptRoot,
    [string]$ConfigXml = 'ODT_SemiAnnual.xml',
    [bool]$Apply       = $false,
    [string]$LogPath   = 'C:\Windows\Temp\ImageBuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "Download-OfficeSource_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

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

$setup  = Join-Path $OdtRoot 'setup.exe'
$config = Join-Path $OdtRoot $ConfigXml
$dataDir = Join-Path $OdtRoot 'Office\Data'

Write-Log "==================================================="
Write-Log "ORG Office source download (ODT /download)"
Write-Log "OdtRoot : $OdtRoot"
Write-Log "Config  : $config"
Write-Log "Apply   : $Apply"
Write-Log "Log     : $LogFile"
Write-Log "==================================================="

# Pre-flight
$fail = $false
if (-not (Test-Path $setup))  { Write-Log "Missing ODT setup.exe: $setup" 'ERROR'; $fail = $true }
if (-not (Test-Path $config)) { Write-Log "Missing ODT config: $config" 'ERROR'; $fail = $true }
if ($fail) { Write-Log "Stage setup.exe (from the Office Deployment Tool) and the config in $OdtRoot, then re-run." 'ERROR'; exit 1 }

# No SourcePath in config: setup.exe resolves Office\Data relative to working directory.
# The download uses -WorkingDirectory $OdtRoot, so Office\Data lands under $OdtRoot.
Write-Log "Working directory for download: $OdtRoot (Office\Data will be created here)" 'OK'

$cmd = "`"$setup`" /download `"$config`""
Write-Log "Command : $cmd  (working dir: $OdtRoot)"

if (-not $Apply) {
    Write-Log "[DRY-RUN] No download performed. Re-run with -Apply `$true to download." 'WARN'
    Write-Log "Next: run with -Apply `$true on a machine with internet." 'NEXT'
    exit 0
}

# Download
Write-Log "Downloading Office source (this can take several minutes and a few GB)..."
$p = Start-Process -FilePath $setup -ArgumentList "/download `"$ConfigXml`"" -WorkingDirectory $OdtRoot -Wait -PassThru -NoNewWindow
$exit = $p.ExitCode
if ($exit -ne 0) { Write-Log "setup.exe /download returned exit $exit (expected 0). Check $OdtRoot for the ODT log." 'ERROR'; exit 1 }
Write-Log "Download completed (exit 0)." 'OK'

# Verify + capture build
if (-not (Test-Path $dataDir)) { Write-Log "Expected source folder not found: $dataDir" 'ERROR'; exit 1 }
$build = (Get-ChildItem $dataDir -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
          Sort-Object Name -Descending | Select-Object -First 1).Name
if (-not $build) { Write-Log "Source downloaded but no build folder under $dataDir - verify manually." 'WARN'; $build = 'UNKNOWN' }
else { Write-Log "Staged Office build: $build" 'OK' }

# Record version + review-by date
$staged   = Get-Date -Format 'yyyy-MM-dd'
$reviewBy = (Get-Date).AddMonths(6).ToString('yyyy-MM-dd')
$verFile  = Join-Path $OdtRoot 'STAGED-OFFICE-VERSION.txt'
@(
    "ORG M365 Apps - staged source"
    "Channel    : Semi-Annual Enterprise"
    "Build      : $build"
    "Staged on  : $staged"
    "Review by  : $reviewBy  (refresh source; SAEC feature updates ~Jan/~Jul)"
    "Config     : $ConfigXml"
    "SourcePath : $OdtRoot\Office\Data\$build"
) | Set-Content -Path $verFile -Encoding ASCII
Write-Log "Wrote version record: $verFile" 'OK'

Write-Log ''
Write-Log "Source ready. Run 10-Build-OemLayer.ps1 then 11-Build-Iso.ps1 to pack the source into the ISO." 'NEXT'
Write-Log "The source rides the ISO to C:\AuditMode\Software\ODT on the reference VM (fully disconnected)." 'NEXT'
exit 0
