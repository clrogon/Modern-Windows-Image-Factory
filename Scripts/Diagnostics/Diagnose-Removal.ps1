# =============================================================================
# ORG Win11 Build - Diagnostic: Bloatware Removal Investigation
# -----------------------------------------------------------------------------
# Run as Administrator AFTER 04-Remove-ProvisionedApps.ps1 has run (with $Apply=$true)
# and BEFORE 09-Dismount-Image.ps1.
#
# The WIM must still be mounted at $MountPath for this to work.
#
# Output is plain text - paste the full output back for analysis.
# =============================================================================

$MountPath   = "E:\WimMount"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AppListPath = Join-Path $ProjectRoot "Lists\ApprovedRemoval-Apps.txt"
$LogPath     = "E:\Logs\Diagnose-Removal-$(Get-Date -Format yyyyMMdd-HHmmss).log"

function Write-Both {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogPath -Value $Message
}

New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

Write-Both "============================================================"
Write-Both "BLOATWARE REMOVAL DIAGNOSTIC"
Write-Both "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Both "============================================================"
Write-Both ""

# ----- Section 1: Is the BUILD WIM actually mounted at E:\WimMount? -----
Write-Both "SECTION 1: Mount status"
Write-Both "------------------------"
$mounted    = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
$buildMount = $mounted | Where-Object { $_.Path -eq $MountPath }
$others     = $mounted | Where-Object { $_.Path -ne $MountPath }

if ($mounted) {
    foreach ($m in $mounted) {
        $tag = if ($m.Path -eq $MountPath) { "[BUILD]" } else { "[unrelated - ignored]" }
        Write-Both "MountPath:  $($m.Path)  $tag"
        Write-Both "ImagePath:  $($m.ImagePath)"
        Write-Both "Index:      $($m.ImageIndex)"
        Write-Both "Status:     $($m.MountStatus)"
        Write-Both ""
    }
}

if (-not $buildMount) {
    Write-Both "ERROR: No build WIM is mounted at $MountPath."
    Write-Both "This diagnostic requires 04-Remove-ProvisionedApps.ps1 to have run with -Apply true"
    Write-Both "(which leaves the WIM mounted), and 09-Dismount-Image.ps1 NOT yet run."
    if ($others) {
        Write-Both ""
        Write-Both "NOTE: other mounts above (e.g. MDT temp mounts) are unrelated and ignored."
        Write-Both "If any show Status 'Invalid', clean them: Clear-WindowsCorruptMountPoint"
    }
    exit 1
}

if ($buildMount.MountStatus -ne 'Ok') {
    Write-Both "ERROR: $MountPath is mounted but Status = $($buildMount.MountStatus) (corrupt)."
    Write-Both "Fix: Dismount-WindowsImage -Path $MountPath -Discard ; Clear-WindowsCorruptMountPoint"
    exit 1
}

if (-not (Test-Path "$MountPath\Windows\System32")) {
    Write-Both "ERROR: $MountPath has no Windows\System32 - mount looks broken."
    Write-Both "Fix: Dismount-WindowsImage -Path $MountPath -Discard ; Clear-WindowsCorruptMountPoint"
    exit 1
}

# ----- Section 2: What does the controlled list say? -----
Write-Both "SECTION 2: Controlled removal list"
Write-Both "----------------------------------"
if (Test-Path $AppListPath) {
    $appsToRemove = Get-Content $AppListPath |
        Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') } |
        ForEach-Object { $_.Trim() }
    Write-Both "Entries in list: $($appsToRemove.Count)"
    foreach ($a in $appsToRemove) { Write-Both "  - $a" }
} else {
    Write-Both "ERROR: Apps list not found at $AppListPath"
}
Write-Both ""

# ----- Section 3: What provisioned AppX packages remain in the offline image? -----
Write-Both "SECTION 3: Provisioned AppX still present in offline image"
Write-Both "----------------------------------------------------------"
Write-Both "(After script 04 ran, these should NOT include items from the list)"
Write-Both ""
$still = Get-AppxProvisionedPackage -Path $MountPath | Sort-Object DisplayName
Write-Both "Count: $($still.Count)"
Write-Both ""
Write-Both ("{0,-50} {1}" -f "DisplayName", "PackageName")
Write-Both ("{0,-50} {1}" -f ("-" * 48), ("-" * 60))
foreach ($p in $still) {
    Write-Both ("{0,-50} {1}" -f $p.DisplayName, $p.PackageName)
}
Write-Both ""

# ----- Section 4: Wildcard match test per list entry -----
Write-Both "SECTION 4: Per-entry wildcard match test"
Write-Both "----------------------------------------"
Write-Both "(Tells us if Get-AppxProvisionedPackage -Path X | Where DisplayName -like *Y* would find each app)"
Write-Both ""
foreach ($a in $appsToRemove) {
    $matched = Get-AppxProvisionedPackage -Path $MountPath |
               Where-Object DisplayName -like "*$a*"
    if ($matched) {
        Write-Both "STILL PRESENT (removal failed?): $a"
        foreach ($m in $matched) {
            Write-Both "    -> $($m.DisplayName) [$($m.PackageName)]"
        }
    } else {
        Write-Both "NOT FOUND (removed or never there): $a"
    }
}
Write-Both ""

# ----- Section 5: Capabilities -----
Write-Both "SECTION 5: Optional capabilities INSTALLED in offline image"
Write-Both "----------------------------------------------------------"
$installedCaps = Get-WindowsCapability -Path $MountPath |
                 Where-Object State -eq 'Installed' |
                 Sort-Object Name
Write-Both "Installed: $($installedCaps.Count)"
foreach ($c in $installedCaps) {
    Write-Both "  $($c.Name)"
}
Write-Both ""

# ----- Section 6: Known system components that are NOT provisioned AppX -----
Write-Both "SECTION 6: System components (NOT removable via AppX mechanism)"
Write-Both "---------------------------------------------------------------"
Write-Both "These ship as Windows features or system binaries, not provisioned AppX."
Write-Both "They CANNOT be removed via Remove-AppxProvisionedPackage."
Write-Both ""
$systemPaths = @{
    "Quick Assist (App)"          = "$MountPath\Windows\SystemApps\MicrosoftWindows.Client.QuickAssist*"
    "Cortana (legacy)"            = "$MountPath\Windows\SystemApps\Microsoft.Windows.Cortana*"
    "Search UI"                   = "$MountPath\Windows\SystemApps\Microsoft.Windows.Search*"
    "Edge (system)"               = "$MountPath\Program Files (x86)\Microsoft\Edge"
    "OneDriveSetup (System32)"    = "$MountPath\Windows\System32\OneDriveSetup.exe"
    "OneDriveSetup (SysWOW64)"    = "$MountPath\Windows\SysWOW64\OneDriveSetup.exe"
    "Recall (Copilot+ PCs)"       = "$MountPath\Windows\System32\Recall*"
    "Web Search (Start Menu)"     = "$MountPath\Windows\SystemApps\Microsoft.BingSearch*"
}
foreach ($name in $systemPaths.Keys) {
    $hit = Get-ChildItem -Path $systemPaths[$name] -ErrorAction SilentlyContinue
    if ($hit) {
        Write-Both "PRESENT:     $name"
        $hit | Select-Object -First 3 | ForEach-Object {
            Write-Both "    $($_.FullName)"
        }
    } else {
        Write-Both "Not present: $name"
    }
}
Write-Both ""

# ----- Section 7: Per-user staging area -----
Write-Both "SECTION 7: Per-user AppX staging (Default profile)"
Write-Both "---------------------------------------------------"
Write-Both "If apps reinstall on first user logon, they may still be staged for the Default user."
Write-Both ""
$stagingDir = "$MountPath\Program Files\WindowsApps"
if (Test-Path $stagingDir) {
    $staged = Get-ChildItem -Path $stagingDir -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name
    Write-Both "Staged packages in $stagingDir : $($staged.Count)"
    foreach ($s in $staged | Select-Object -First 40) {
        Write-Both "  $($s.Name)"
    }
    if ($staged.Count -gt 40) {
        Write-Both "  ... (truncated, $($staged.Count - 40) more)"
    }
} else {
    Write-Both "WindowsApps folder not accessible (normal if takeown/icacls not used)"
}
Write-Both ""

# ----- Section 8: Suggested next steps -----
Write-Both "============================================================"
Write-Both "DIAGNOSTIC COMPLETE"
Write-Both "Log: $LogPath"
Write-Both "============================================================"
Write-Both ""
Write-Both "Paste the full output back for analysis."
