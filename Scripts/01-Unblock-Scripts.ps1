# =============================================================================
# Windows 11 Image Build - Script 00: Unblock Scripts and Prepare
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001
# Owner: IT Solutions Architecture
#
# Run FIRST after extracting the build environment from a ZIP.
#
# What it does:
#   1. Removes Mark-of-the-Web (Zone.Identifier ADS) from all .ps1 / .cmd files
#   2. Verifies PowerShell execution policy
#   3. Creates required runtime folders (Logs, mount targets)
#   4. Reports any blocked files it could not unblock
#
# This eliminates the "not digitally signed" error when running scripts from
# a downloaded/copied ZIP archive.
#
# Run as Administrator. No $Apply flag - this script is read-mostly and safe.
# This script WILL FAIL with an access-denied error if not run elevated -
# Get-WindowsImage/mount-path checks and folder creation under system-managed
# drive roots require admin rights.
# =============================================================================
#Requires -RunAsAdministrator

$ProjectRoot = Split-Path -Parent $PSScriptRoot   # parent of \Scripts\
$LogPath     = Join-Path $ProjectRoot "Logs\UnblockScripts-$(Get-Date -Format yyyyMMdd-HHmmss).log"

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

Write-Log "ORG Win11 Build Environment Prep starting"
Write-Log "Project root: $ProjectRoot"

# ----- 1. Unblock all scripts and cmd files -----
Write-Log ""
Write-Log "Step 1: Unblocking scripts and config files"

$targets = Get-ChildItem -Path $ProjectRoot -Recurse -File -Include `
    *.ps1, *.cmd, *.bat, *.psm1, *.psd1, *.xml, *.txt -ErrorAction SilentlyContinue

$unblockCount = 0
$failCount    = 0

foreach ($f in $targets) {
    try {
        # Test if file has Zone.Identifier ADS (mark of the web)
        $zone = Get-Item -Path "$($f.FullName):Zone.Identifier" -ErrorAction SilentlyContinue
        if ($zone) {
            Unblock-File -Path $f.FullName -ErrorAction Stop
            Write-Log "  Unblocked: $($f.FullName.Substring($ProjectRoot.Length + 1))" 'OK'
            $unblockCount++
        }
    } catch {
        Write-Log "  FAILED to unblock: $($f.FullName) - $_" 'ERROR'
        $failCount++
    }
}

Write-Log "Unblock complete: $unblockCount file(s) unblocked, $failCount failure(s)" 'OK'

# ----- 2. Check execution policy -----
Write-Log ""
Write-Log "Step 2: Execution policy check"

$policy = Get-ExecutionPolicy -Scope CurrentUser
Write-Log "Current user execution policy: $policy"

if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Log "Execution policy '$policy' will block running these unsigned local scripts." 'WARN'
    Write-Log "Recommended for build environment: RemoteSigned" 'WARN'
    Write-Log "To change for this user only:" 'INFO'
    Write-Log "  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" 'INFO'
} else {
    Write-Log "Execution policy '$policy' is compatible with these scripts." 'OK'
}

# ----- 3. Ensure runtime folders exist -----
Write-Log ""
Write-Log "Step 3: Runtime folder check"

$runtimeFolders = @(
    (Join-Path $ProjectRoot "Logs"),
    "E:\WimMount"
)

foreach ($f in $runtimeFolders) {
    if (-not (Test-Path $f)) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
        Write-Log "  Created: $f" 'OK'
    } else {
        Write-Log "  Exists:  $f"
    }
}

# ----- 4. Check WimMount is empty (required by Mount-WindowsImage) -----
Write-Log ""
Write-Log "Step 4: WimMount cleanliness check"

$mountPath = "E:\WimMount"
$mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
$thisMount = $mountedImages | Where-Object { $_.Path -eq $mountPath }

if ($thisMount) {
    Write-Log "An image is currently mounted at $mountPath" 'WARN'
    Write-Log "  ImagePath: $($thisMount.ImagePath)"
    Write-Log "  Status:    $($thisMount.MountStatus)"
    Write-Log "  This will block Phase 03 (Offline Servicing). Resolve before continuing." 'WARN'
    Write-Log "  To save and clear:" 'INFO'
    Write-Log "    Dismount-WindowsImage -Path $mountPath -Save" 'INFO'
    Write-Log "  To discard changes and clear:" 'INFO'
    Write-Log "    Dismount-WindowsImage -Path $mountPath -Discard" 'INFO'
} else {
    $items = Get-ChildItem -Path $mountPath -Force -ErrorAction SilentlyContinue
    if ($items) {
        Write-Log "$mountPath is NOT empty and no image is mounted." 'WARN'
        Write-Log "Mount-WindowsImage will refuse to mount into a non-empty directory." 'WARN'
        Write-Log "Items found:" 'WARN'
        $items | Select-Object -First 10 | ForEach-Object {
            Write-Log "  $($_.FullName)" 'WARN'
        }
        Write-Log "Action: review and clean before running 04-Remove-ProvisionedApps.ps1" 'WARN'
        Write-Log "  Remove-Item -Path '$mountPath\*' -Recurse -Force" 'INFO'
    } else {
        Write-Log "$mountPath is clean and ready" 'OK'
    }
}

Write-Log ""
Write-Log "Prep complete. Log: $LogPath" 'OK'
Write-Log ""
Write-Log "Next: run 02-Extract-Iso.ps1" 'NEXT'
