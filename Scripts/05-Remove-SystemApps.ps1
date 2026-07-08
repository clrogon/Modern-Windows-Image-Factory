# =============================================================================
# Windows 11 Image Build - Script 05: Offline System Component Removal
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Section 3.4 (extension)
# Owner: IT Solutions Architecture
#
# Removes system components that ARE NOT provisioned AppX packages and
# therefore cannot be removed by 04-Remove-ProvisionedApps.ps1:
#
#   - Quick Assist (Win11 25H2 ships as SystemApp)
#   - Cortana (legacy system app, may still ship by name)
#   - Web Search in Start Menu (BingSearch SystemApp)
#   - Recall (Copilot+ PCs - present even when feature disabled)
#
# Targets folders under: <Mount>\Windows\SystemApps\
#
# Prerequisite: WIM is currently mounted at $MountPath by 04-Remove-ProvisionedApps.ps1
# running WITH -Apply. Dry-run mode (no -Apply) never mounts anything, so if
# you skipped straight to this script, or ran 04 without -Apply, there is
# nothing mounted here yet - see the error below for exactly that check.
# Run BEFORE 06-Remove-OneDrive.ps1 (logical ordering with other offline
# file removals; both happen while WIM is mounted).
#
# Run as Administrator. Pass -Apply to execute (default: dry-run).
# Default -MountPath comes from Scripts\BuildConfig.psd1.
# =============================================================================
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$MountPath
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config      = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'BuildConfig.psd1')
if (-not $MountPath) { $MountPath = $Config.MountPath }
$LogPath     = Join-Path $ProjectRoot "Logs\RemoveSystemApps-$(Get-Date -Format yyyyMMdd-HHmmss).log"

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

# ----- Guard: WIM must be mounted -----
if (-not (Test-Path $MountPath)) {
    throw "Mount path does not exist: $MountPath. Run 04-Remove-ProvisionedApps.ps1 -Apply first."
}
if (-not (Test-Path "$MountPath\Windows\System32")) {
    throw "Mount path exists but contains no Windows image (missing Windows\System32) at $MountPath. " +
          "Most likely cause: 04-Remove-ProvisionedApps.ps1 was run WITHOUT -Apply (dry-run doesn't " +
          "mount anything), or the image was already dismounted (e.g. 09-Dismount-Image.ps1 already ran). " +
          "Check current mounts with: Get-WindowsImage -Mounted"
}

$mountedHere = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -eq $MountPath }
if (-not $mountedHere) {
    Write-Log "WARNING: Get-WindowsImage -Mounted does not report a mount at $MountPath." 'WARN'
    Write-Log "Continuing - file system path exists. Confirm with: Get-WindowsImage -Mounted" 'WARN'
}

Write-Log "DRY-RUN MODE: $(-not $Apply)"
Write-Log "Mount: $MountPath"
Write-Log ""

# ----- System apps to remove (folder name patterns under Windows\SystemApps) -----
# Each entry: friendly name, folder pattern (under Windows\SystemApps\)
$systemAppsToRemove = @(
    @{ Name = "Quick Assist";          Pattern = "MicrosoftWindows.Client.QuickAssist_*" }
    @{ Name = "Quick Assist (legacy)"; Pattern = "App.Support.QuickAssist_*"               }
    @{ Name = "Cortana (legacy)";      Pattern = "Microsoft.Windows.Cortana_*"             }
    @{ Name = "Web Search (BingSearch SystemApp)"; Pattern = "Microsoft.BingSearch_*"      }
    @{ Name = "Web Search (legacy)";   Pattern = "Microsoft.Windows.Search_*"              }
)

# ----- Stats -----
$stats = @{ Found = 0; Removed = 0; Failed = 0; NotPresent = 0 }
$systemAppsRoot = "$MountPath\Windows\SystemApps"

if (-not (Test-Path $systemAppsRoot)) {
    Write-Log "SystemApps folder not found at $systemAppsRoot - is this really a Windows image?" 'ERROR'
    throw "Cannot continue without SystemApps folder."
}

Write-Log "=== System Component Removal ==="
Write-Log ""

foreach ($entry in $systemAppsToRemove) {
    $name    = $entry.Name
    $pattern = $entry.Pattern
    $fullGlob = Join-Path $systemAppsRoot $pattern

    $candidates = @(Get-ChildItem -Path $fullGlob -Directory -ErrorAction SilentlyContinue)

    if ($candidates.Count -eq 0) {
        Write-Log ("NOT PRESENT  {0,-50}  (pattern: {1})" -f $name, $pattern) 'SKIP'
        $stats.NotPresent++
        continue
    }

    foreach ($folder in $candidates) {
        $stats.Found++
        Write-Log ("FOUND        {0,-50}  -> {1}" -f $name, $folder.FullName)

        if (-not $Apply) {
            Write-Log ("  DRY-RUN    would takeown + icacls + Remove-Item recursive") 'INFO'
            continue
        }

        try {
            # SystemApps folders are owned by TrustedInstaller. takeown + icacls are required.
            & takeown.exe /F $folder.FullName /R /A /D Y 2>&1 | Out-Null
            & icacls.exe $folder.FullName /grant "BUILTIN\Administrators:F" /T /C /Q 2>&1 | Out-Null

            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop

            if (Test-Path $folder.FullName) {
                Write-Log ("  FAIL       folder still present after Remove-Item: {0}" -f $folder.FullName) 'ERROR'
                $stats.Failed++
            } else {
                Write-Log ("  OK         removed: {0}" -f $folder.Name) 'OK'
                $stats.Removed++
            }
        } catch {
            Write-Log ("  FAIL       {0}: {1}" -f $folder.Name, $_.Exception.Message) 'ERROR'
            $stats.Failed++
        }
    }
}

# ----- Summary -----
Write-Log ""
Write-Log "===================================="
Write-Log "Phase 05 Summary" 'OK'
Write-Log "------------------------------------"
Write-Log "Targets in list:     $($systemAppsToRemove.Count)"
Write-Log "Found in image:      $($stats.Found)"
Write-Log "Successfully removed: $($stats.Removed)"
Write-Log "Failed:              $($stats.Failed)"
Write-Log "Not present:         $($stats.NotPresent)"

if ($stats.Failed -gt 0) {
    Write-Log ""
    Write-Log "FAILURES occurred. WIM is still mounted - investigate before running 04 and 05." 'ERROR'
}

Write-Log ""
Write-Log "WIM STILL MOUNTED at $MountPath" 'OK'
Write-Log "Next: run 06-Remove-OneDrive.ps1" 'NEXT'
Write-Log "===================================="
