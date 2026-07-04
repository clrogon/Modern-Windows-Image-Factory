# =============================================================================
# Windows 11 Image Build - Script 03a: DIAGNOSE provisioned apps + capabilities
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Appendix D troubleshooting
#
# Read-only diagnostic. Run AFTER 04-Remove-ProvisionedApps.ps1 has mounted the WIM
# (WIM must be mounted at $MountPath). Dumps:
#   - Every provisioned AppX in the offline image (full package names)
#   - Every Windows capability in the offline image (full names)
#   - Match analysis: for each entry in ApprovedRemoval-Apps.txt and
#     ApprovedRemoval-Capabilities.txt, shows whether it matches anything
#
# Use this to figure out WHY a removal target is being skipped:
#   - "Not present" in the log means the wildcard matched zero packages
#   - This script tells you what IS in the image so you can fix the list
# =============================================================================

$MountPath   = "E:\WimMount"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\Diagnose-AppxAndCapabilities-$(Get-Date -Format yyyyMMdd-HHmmss).log"
$AppListPath = Join-Path $ProjectRoot "Lists\ApprovedRemoval-Apps.txt"
$CapListPath = Join-Path $ProjectRoot "Lists\ApprovedRemoval-Capabilities.txt"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}
New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

# Guard
if (-not (Test-Path "$MountPath\Windows\System32")) {
    throw "WIM not mounted at $MountPath. Run 04-Remove-ProvisionedApps.ps1 first (it leaves the WIM mounted)."
}

# Confirm WIM is actually mounted via DISM
$mountedHere = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -eq $MountPath }
if (-not $mountedHere) {
    Write-Log "WARNING: $MountPath exists but Get-WindowsImage -Mounted does not list it" 'WARN'
}

# ============================================================================
# SECTION 1: All provisioned AppX packages in the offline image
# ============================================================================
Write-Log ""
Write-Log "=================================================="
Write-Log "SECTION 1: Provisioned AppX packages in offline image"
Write-Log "=================================================="

$allApps = Get-AppxProvisionedPackage -Path $MountPath -ErrorAction Stop |
           Sort-Object DisplayName

Write-Log "Total provisioned AppX packages: $($allApps.Count)"
Write-Log ""

foreach ($app in $allApps) {
    Write-Log ("  {0,-50}  {1}" -f $app.DisplayName, $app.PackageName)
}

# ============================================================================
# SECTION 2: Match analysis for ApprovedRemoval-Apps.txt
# ============================================================================
if (Test-Path $AppListPath) {
    Write-Log ""
    Write-Log "=================================================="
    Write-Log "SECTION 2: Match analysis for ApprovedRemoval-Apps.txt"
    Write-Log "=================================================="

    $appsToRemove = Get-Content $AppListPath |
        Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
        ForEach-Object { $_.Trim() }

    $unmatched = @()
    foreach ($wanted in $appsToRemove) {
        # NOTE: $matches is a PowerShell automatic variable - use $found instead.
        $found = @($allApps | Where-Object { $_.DisplayName -like "*$wanted*" })
        if ($found.Count -gt 0) {
            Write-Log ("MATCH    {0,-40}  -> {1} package(s)" -f $wanted, $found.Count) 'OK'
            foreach ($m in $found) {
                Write-Log ("           {0}" -f $m.DisplayName) 'OK'
            }
        } else {
            Write-Log ("NO MATCH {0,-40}  -> not present in image" -f $wanted) 'WARN'
            $unmatched += $wanted
        }
    }

    Write-Log ""
    Write-Log "Summary: $(($appsToRemove.Count) - $unmatched.Count)/$($appsToRemove.Count) entries matched at least one package"
    if ($unmatched) {
        Write-Log "Unmatched entries (potentially stale list items or renamed packages):" 'WARN'
        foreach ($u in $unmatched) { Write-Log "  - $u" 'WARN' }
    }
} else {
    Write-Log "ApprovedRemoval-Apps.txt not found at $AppListPath" 'WARN'
}

# ============================================================================
# SECTION 3: All Windows capabilities in the offline image
# ============================================================================
Write-Log ""
Write-Log "=================================================="
Write-Log "SECTION 3: Windows capabilities in offline image"
Write-Log "=================================================="

$allCaps = Get-WindowsCapability -Path $MountPath -ErrorAction Stop |
           Sort-Object Name

$installed = $allCaps | Where-Object { $_.State -eq 'Installed' }
$notInst   = $allCaps | Where-Object { $_.State -ne 'Installed' }
Write-Log "Total capabilities: $($allCaps.Count)  Installed: $($installed.Count)  Not present: $($notInst.Count)"
Write-Log ""

Write-Log "INSTALLED capabilities (these CAN be removed):"
foreach ($cap in $installed) {
    Write-Log ("  {0}" -f $cap.Name)
}

# ============================================================================
# SECTION 4: Match analysis for ApprovedRemoval-Capabilities.txt
# ============================================================================
if (Test-Path $CapListPath) {
    Write-Log ""
    Write-Log "=================================================="
    Write-Log "SECTION 4: Match analysis for ApprovedRemoval-Capabilities.txt"
    Write-Log "=================================================="

    $capsToRemove = Get-Content $CapListPath |
        Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
        ForEach-Object { $_.Trim() }

    $capUnmatched = @()
    foreach ($wanted in $capsToRemove) {
        # Capability list uses EXACT name match - not wildcard
        $exact = $allCaps | Where-Object { $_.Name -eq $wanted }
        $partial = $allCaps | Where-Object { $_.Name -like "*$wanted*" -and $_.Name -ne $wanted }

        if ($exact) {
            if ($exact.State -eq 'Installed') {
                Write-Log ("EXACT    {0}  (Installed - WILL be removed)" -f $wanted) 'OK'
            } else {
                Write-Log ("EXACT    {0}  (State: $($exact.State) - already gone)" -f $wanted) 'SKIP'
            }
        } elseif ($partial) {
            Write-Log ("PARTIAL  {0}  (exact name not found, partial matches below - LIST IS WRONG)" -f $wanted) 'WARN'
            foreach ($p in $partial) {
                Write-Log ("           Did you mean: {0} (State: {1})" -f $p.Name, $p.State) 'WARN'
            }
            $capUnmatched += $wanted
        } else {
            Write-Log ("NO MATCH {0}  (not present in image)" -f $wanted) 'WARN'
            $capUnmatched += $wanted
        }
    }

    Write-Log ""
    Write-Log "Summary: $(($capsToRemove.Count) - $capUnmatched.Count)/$($capsToRemove.Count) entries matched"
    if ($capUnmatched) {
        Write-Log "Action: edit ApprovedRemoval-Capabilities.txt and fix the entries listed above." 'WARN'
        Write-Log "Capability names are VERSIONED (e.g., 'Browser.InternetExplorer~~~~0.0.11.0')." 'INFO'
        Write-Log "Use Section 3 output above to copy the exact name."
    }
} else {
    Write-Log "ApprovedRemoval-Capabilities.txt not found at $CapListPath" 'WARN'
}

Write-Log ""
Write-Log "=================================================="
Write-Log "Diagnostic complete. Log: $LogPath"
Write-Log "=================================================="
