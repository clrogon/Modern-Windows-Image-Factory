# =============================================================================
# Windows 11 Image Build - Script 03: Offline DISM Servicing
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Section 3.4
# Owner: IT Solutions Architecture
#
# Removes provisioned apps and Windows capabilities from install.wim BEFORE
# first boot. Driven by controlled lists in <ProjectRoot>\Lists\.
#
# Mounts the WIM and LEAVES IT MOUNTED so script 04 (OneDrive removal) can
# operate on the offline image. Script 05 handles dismount.
#
# v2.2 changes (vs prior versions):
#   - Apps: wildcard match preserved, but EVERY list entry is reported as
#     MATCH / NO MATCH so renamed-package gaps are visible
#   - Capabilities: now supports both exact name AND prefix match. Microsoft
#     versions capability names (e.g. Browser.InternetExplorer~~~~0.0.11.0);
#     listing the prefix is enough.
#   - Final summary reports counts: matched, removed, skipped, failed
#   - Non-zero failed count surfaces with a red WARNING line
#
# Run as Administrator. Pass -Apply to execute (default: dry-run).
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Apply
)

$WimPath     = "E:\ISO\Win11_25H2_7\sources\install.wim"
$MountPath   = "E:\WimMount"
$Index       = 3   # Windows 11 Enterprise (confirm via 02-Extract-Iso.ps1)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\RemoveProvisionedApps-$(Get-Date -Format yyyyMMdd-HHmmss).log"
$AppListPath = Join-Path $ProjectRoot "Lists\ApprovedRemoval-Apps.txt"
$CapListPath = Join-Path $ProjectRoot "Lists\ApprovedRemoval-Capabilities.txt"

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

# ----- Pre-flight -----
if (-not (Test-Path $WimPath))     { throw "WIM not found at $WimPath - run 02-Extract-Iso.ps1 first." }
if (-not (Test-Path $AppListPath)) { throw "App list not found at $AppListPath" }
if (-not (Test-Path $CapListPath)) { throw "Capability list not found at $CapListPath" }

$wimItem = Get-Item $WimPath
if ($wimItem.IsReadOnly) {
    throw "install.wim is read-only. Run: Get-Item '$WimPath' | %{ `$_.IsReadOnly = `$false }"
}

if (-not (Test-Path $MountPath)) {
    New-Item -ItemType Directory -Path $MountPath -Force | Out-Null
}
$existing = Get-ChildItem -Path $MountPath -Force -ErrorAction SilentlyContinue
if ($existing) {
    $alreadyMounted = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                      Where-Object { $_.Path -eq $MountPath }
    if ($alreadyMounted) {
        throw @"
An image is already mounted at $MountPath
  ImagePath: $($alreadyMounted.ImagePath)
  Status:    $($alreadyMounted.MountStatus)
Resolve before continuing:
  Dismount-WindowsImage -Path '$MountPath' -Save     (or -Discard)
"@
    } else {
        throw "Mount path $MountPath is not empty. Clean: Remove-Item -Path '$MountPath\*' -Recurse -Force"
    }
}

# Edition check
$selected = Get-WindowsImage -ImagePath $WimPath | Where-Object ImageIndex -eq $Index
if (-not $selected) {
    Write-Host "Available images in $WimPath :" -ForegroundColor Yellow
    Get-WindowsImage -ImagePath $WimPath | Format-Table ImageIndex, ImageName
    throw "Index $Index does not exist in this WIM."
}

switch -Wildcard ($selected.ImageName) {
    "*Enterprise*" {
        Write-Host "PRODUCTION-READY EDITION: index $Index = $($selected.ImageName)" -ForegroundColor Green
        $WimTag = "PROD"
    }
    "*Pro*" {
        Write-Host "WARNING: testing-only edition (Pro)" -ForegroundColor Yellow
        $confirm = Read-Host "Type CONTINUE to acknowledge POC limitations and proceed"
        if ($confirm -ne 'CONTINUE') { throw "Aborted by operator." }
        $WimTag = "POC-Pro"
    }
    default { throw "Index $Index is '$($selected.ImageName)'. Only Enterprise or Pro permitted." }
}

$AppsToRemove = Get-Content $AppListPath |
    Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
    ForEach-Object { $_.Trim() }

$CapabilitiesToRemove = Get-Content $CapListPath |
    Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
    ForEach-Object { $_.Trim() }

Write-Log "Build tag: $WimTag"
Write-Log "DRY-RUN MODE: $(-not $Apply)"
Write-Log "WIM: $WimPath (index $Index = $($selected.ImageName))"
Write-Log "Mount: $MountPath"
Write-Log "Apps to remove (list entries): $($AppsToRemove.Count)"
Write-Log "Capabilities to remove (list entries): $($CapabilitiesToRemove.Count)"

# ----- Mount -----
Write-Log ""
Write-Log "Mounting WIM at $MountPath"
if ($Apply) {
    Mount-WindowsImage -ImagePath $WimPath -Index $Index -Path $MountPath
    Write-Log "Mount succeeded" 'OK'
} else {
    Write-Log "DRY-RUN: would mount; for accurate dry-run, run Diagnostics\Diagnose-AppxAndCapabilities.ps1 against a real mount" 'INFO'
}

# In dry-run, we cannot enumerate offline AppX/capabilities. Bail with guidance.
if (-not $Apply) {
    Write-Log ""
    Write-Log "DRY-RUN complete (no mount performed)." 'OK'
    Write-Log "Set `$Apply = `$true and re-run to mount and service." 'INFO'
    Write-Log "For accurate per-package match analysis, run Diagnostics\Diagnose-AppxAndCapabilities.ps1 after a real mount."
    return
}

# ----- Enumerate what's actually in the image -----
Write-Log ""
Write-Log "Enumerating provisioned AppX packages in offline image..."
$allApps = Get-AppxProvisionedPackage -Path $MountPath
Write-Log "Found $($allApps.Count) provisioned AppX packages"

Write-Log "Enumerating Windows capabilities in offline image..."
$allCaps = Get-WindowsCapability -Path $MountPath
$installedCaps = $allCaps | Where-Object { $_.State -eq 'Installed' }
Write-Log "Found $($allCaps.Count) capabilities ($($installedCaps.Count) installed)"

# ----- Remove provisioned apps -----
Write-Log ""
Write-Log "=== App removal ==="
$appStats = @{ Matched = 0; Removed = 0; Skipped = 0; Failed = 0; Unmatched = @() }

foreach ($wanted in $AppsToRemove) {
    # NOTE: $matches is a PowerShell AUTOMATIC variable (populated by -match operator).
    # Using it as a regular variable causes silent overwrites. Use $found instead.
    $found = @($allApps | Where-Object { $_.DisplayName -like "*$wanted*" })

    if ($found.Count -eq 0) {
        Write-Log ("NO MATCH  {0,-40}  not present in image - check list for stale entry" -f $wanted) 'WARN'
        $appStats.Unmatched += $wanted
        continue
    }

    foreach ($pkg in $found) {
        $appStats.Matched++
        Write-Log ("Removing  {0,-40}  ({1})" -f $pkg.DisplayName, $pkg.PackageName)
        try {
            Remove-AppxProvisionedPackage -Path $MountPath -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null

            # VERIFY the removal actually took effect by re-querying
            $stillThere = Get-AppxProvisionedPackage -Path $MountPath |
                          Where-Object { $_.PackageName -eq $pkg.PackageName }
            if ($stillThere) {
                Write-Log ("  FAIL    {0} - command succeeded but package STILL PRESENT after removal" -f $pkg.DisplayName) 'ERROR'
                $appStats.Failed++
            } else {
                Write-Log ("  OK      {0}  (verified removed)" -f $pkg.DisplayName) 'OK'
                $appStats.Removed++
            }
        } catch {
            Write-Log ("  FAIL    {0} - {1}" -f $pkg.DisplayName, $_.Exception.Message) 'ERROR'
            $appStats.Failed++
        }
    }
}

# ----- Remove capabilities -----
Write-Log ""
Write-Log "=== Capability removal ==="
$capStats = @{ Matched = 0; Removed = 0; Skipped = 0; Failed = 0; Unmatched = @() }

foreach ($wanted in $CapabilitiesToRemove) {
    # Capability names are versioned: Browser.InternetExplorer~~~~0.0.11.0
    # Accept both exact match and prefix-up-to-tilde match.
    # NOTE: $matches is a PowerShell automatic variable - use $found instead.
    $exact = $allCaps | Where-Object { $_.Name -eq $wanted }
    $prefix = if (-not $exact) {
        $allCaps | Where-Object { $_.Name -like "$wanted~*" -or $_.Name -like "$wanted.*" }
    } else { @() }

    $found = @(if ($exact) { $exact } else { $prefix })

    if ($found.Count -eq 0) {
        Write-Log ("NO MATCH  {0,-50}  not in image - check list / wrong version suffix" -f $wanted) 'WARN'
        $capStats.Unmatched += $wanted
        continue
    }

    foreach ($cap in $found) {
        $capStats.Matched++
        if ($cap.State -ne 'Installed') {
            Write-Log ("SKIP      {0}  state={1} (already absent)" -f $cap.Name, $cap.State) 'SKIP'
            $capStats.Skipped++
            continue
        }
        Write-Log ("Removing  {0}" -f $cap.Name)
        try {
            Remove-WindowsCapability -Path $MountPath -Name $cap.Name -ErrorAction Stop | Out-Null

            # VERIFY removal
            $verifyCap = Get-WindowsCapability -Path $MountPath -Name $cap.Name -ErrorAction SilentlyContinue
            if ($verifyCap -and $verifyCap.State -eq 'Installed') {
                Write-Log ("  FAIL    {0} - command succeeded but capability STILL INSTALLED" -f $cap.Name) 'ERROR'
                $capStats.Failed++
            } else {
                Write-Log ("  OK      {0}  (verified removed)" -f $cap.Name) 'OK'
                $capStats.Removed++
            }
        } catch {
            Write-Log ("  FAIL    {0} - {1}" -f $cap.Name, $_.Exception.Message) 'ERROR'
            $capStats.Failed++
        }
    }
}

# ----- Summary -----
Write-Log ""
Write-Log "===================================="
Write-Log "Phase 03 Summary" 'OK'
Write-Log "------------------------------------"
Write-Log "Apps        Matched: $($appStats.Matched)  Removed: $($appStats.Removed)  Failed: $($appStats.Failed)  Unmatched list entries: $($appStats.Unmatched.Count)"
Write-Log "Capabilities Matched: $($capStats.Matched)  Removed: $($capStats.Removed)  Skipped (already absent): $($capStats.Skipped)  Failed: $($capStats.Failed)  Unmatched list entries: $($capStats.Unmatched.Count)"

if ($appStats.Unmatched.Count -gt 0) {
    Write-Log ""
    Write-Log "App list entries with NO match in image (potentially stale):" 'WARN'
    foreach ($u in $appStats.Unmatched) { Write-Log "  - $u" 'WARN' }
    Write-Log "Action: run .\Diagnostics\Diagnose-AppxAndCapabilities.ps1 to see what AppX names ARE present." 'INFO'
}
if ($capStats.Unmatched.Count -gt 0) {
    Write-Log ""
    Write-Log "Capability list entries with NO match in image:" 'WARN'
    foreach ($u in $capStats.Unmatched) { Write-Log "  - $u" 'WARN' }
    Write-Log "Action: capability names are VERSIONED. Run .\Diagnostics\Diagnose-AppxAndCapabilities.ps1 for exact names." 'INFO'
}
if ($appStats.Failed -gt 0 -or $capStats.Failed -gt 0) {
    Write-Log ""
    Write-Log "FAILURES occurred during removal. WIM is still mounted - investigate before running 04 and 05." 'ERROR'
}

Write-Log ""
Write-Log "WIM STILL MOUNTED at $MountPath" 'OK'
Write-Log "Next: run 05-Remove-SystemApps.ps1 (run Diagnostics\\Diagnose-AppxAndCapabilities.ps1 first if unsure of names)" 'NEXT'
Write-Log "Then: 09-Dismount-Image.ps1"
Write-Log "===================================="
