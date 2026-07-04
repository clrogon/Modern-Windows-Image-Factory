# =============================================================================
# Windows 11 Image Build - Script 02: Setup Build Environment
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001
# Owner: IT Solutions Architecture
#
# One-time setup. Verifies the project layout, prompts to copy known-missing
# assets, and confirms tool availability (ADK, robocopy, etc).
#
# Run as Administrator. No $Apply flag - this script is read-only verification.
# =============================================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\02-Setup-$(Get-Date -Format yyyyMMdd-HHmmss).log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'NEXT'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
    Add-Content -Path $LogPath -Value $line
}

New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

Write-Log "Build environment verification"
Write-Log "Project root: $ProjectRoot"
Write-Log ""

# ----- Required folders -----
$expectedFolders = @(
    'Scripts', 'Lists', 'SCT', 'LGPO', 'GPO-Backup', 'unattend',
    'Branding', 'Defaults', 'Drivers-SCCM',
    'OEM-Template', 'Logs'
)

Write-Log "Folder structure check:"
foreach ($f in $expectedFolders) {
    $path = Join-Path $ProjectRoot $f
    if (Test-Path $path) {
        Write-Log "  OK:      $f"
    } else {
        Write-Log "  MISSING: $f - creating" 'WARN'
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# ----- Required input files / templates -----
Write-Log ""
Write-Log "Required file check:"

$mandatory = @{
    "Lists\ApprovedRemoval-Apps.txt"          = "Approved provisioned-app removal list"
    "Lists\ApprovedRemoval-Capabilities.txt"  = "Approved capability removal list"
    "OEM-Template\SetupComplete.cmd"          = "SetupComplete script (runs as SYSTEM at end of Setup)"
}

$missingMandatory = $false
foreach ($f in $mandatory.Keys) {
    $path = Join-Path $ProjectRoot $f
    if (Test-Path $path) {
        Write-Log "  OK:      $f"
    } else {
        Write-Log "  MISSING: $f - $($mandatory[$f])" 'ERROR'
        $missingMandatory = $true
    }
}

# ----- Optional input files -----
Write-Log ""
Write-Log "Optional file check (populate before running later phases):"

$optional = @{
    "Branding\*.jpg"                  = "Wallpapers / lock screen"
    "Drivers-SCCM\*"                  = "Extracted SCCM driver trees"
    "OEM-Template\OEMLogo.bmp"        = "OEM logo for Settings -> About (24-bit BMP max 120x120)"
    "SCT\*"                           = "Microsoft Security Compliance Toolkit (download separately)"
    "LGPO\LGPO.exe"                   = "LGPO.exe (ships with SCT)"
    "unattend\unattend-reference.xml" = "Sysprep answer file (build with Windows SIM)"
    "Defaults\Default_Apps_Windows11.xml" = "Default file associations"
    "Defaults\Corporate_wifi_template.xml" = "Wi-Fi profile template"
}

foreach ($f in $optional.Keys) {
    $path  = Join-Path $ProjectRoot $f
    $found = @(Get-ChildItem -Path (Split-Path $path -Parent) -Filter (Split-Path $path -Leaf) -ErrorAction SilentlyContinue)
    if ($found.Count -gt 0) {
        Write-Log "  OK:      $f ($($found.Count) item(s))"
    } else {
        Write-Log "  NEEDED:  $f - $($optional[$f])" 'INFO'
    }
}

# ----- Tool availability -----
Write-Log ""
Write-Log "Tool availability check:"

# Windows ADK / oscdimg
$adkCandidates = @(
    "E:\Windows assessment and deployed kit\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "E:\Windows Assessment and Deployment Kit\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
)
$oscdimg = $null
foreach ($c in $adkCandidates) {
    if (Test-Path $c) { $oscdimg = $c; break }
}
if ($oscdimg) {
    Write-Log "  OK:      ADK / oscdimg.exe -> $oscdimg" 'OK'
    Write-Log "           Set this path as `$ADKPath in 11-Build-Iso.ps1"
} else {
    Write-Log "  MISSING: oscdimg.exe - install Windows ADK (Deployment Tools feature)" 'ERROR'
    $missingMandatory = $true
}

# robocopy (built into Windows)
if (Get-Command robocopy -ErrorAction SilentlyContinue) {
    Write-Log "  OK:      robocopy"
} else {
    Write-Log "  MISSING: robocopy" 'ERROR'
}

# DISM cmdlets
if (Get-Command Mount-WindowsImage -ErrorAction SilentlyContinue) {
    Write-Log "  OK:      Mount-WindowsImage cmdlet"
} else {
    Write-Log "  MISSING: Mount-WindowsImage - install RSAT / DISM PowerShell module" 'ERROR'
    $missingMandatory = $true
}

# ----- Summary -----
Write-Log ""
Write-Log "===================================="
if ($missingMandatory) {
    Write-Log "Setup INCOMPLETE - resolve missing items above" 'ERROR'
} else {
    Write-Log "Setup OK - ready to proceed" 'OK'
    Write-Log "Next: run 04-Remove-ProvisionedApps.ps1" 'NEXT'
}
Write-Log "Log: $LogPath"
Write-Log "===================================="
