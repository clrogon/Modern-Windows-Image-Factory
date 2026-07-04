# =============================================================================
# Windows 11 Image Build - Script 01: Extract ISO + Clear Read-Only
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Section 3.1.1
# Owner: IT Solutions Architecture
#
# Mounts a Windows 11 ISO, copies the contents to a working folder, then
# clears the read-only attribute from all extracted files. The read-only
# attribute travels with ISO file copies and breaks subsequent phases
# (mounting the WIM, writing OEM folders, oscdimg packing).
#
# Run as Administrator. Set $Apply = $true to execute (default: dry-run).
# =============================================================================

$Apply       = $true

# --- Source and destination ---
$ISOFile     = "E:\ISO\SW_DVD9_Win_Pro_11_25H2.7_64BIT_English_Pro_Ent_EDU_N_MLF_X24-30433.ISO"
$Destination = "E:\ISO\Win11_25H2_7"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\ExtractIso-$(Get-Date -Format yyyyMMdd-HHmmss).log"

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
if (-not (Test-Path $ISOFile)) {
    throw "ISO not found: $ISOFile"
}

Write-Log "ISO: $ISOFile"
Write-Log "Destination: $Destination"
Write-Log "DRY-RUN MODE: $(-not $Apply)"

if (Test-Path $Destination) {
    Write-Log "Destination already exists: $Destination" 'WARN'
    if ($Apply) {
        $confirm = Read-Host "Type CONTINUE to overwrite destination, anything else to abort"
        if ($confirm -ne 'CONTINUE') { throw "Aborted by operator." }
        Write-Log "Removing existing destination contents"
        # Clear read-only first in case earlier extract left them
        Get-ChildItem -Path $Destination -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { if ($_.IsReadOnly) { $_.IsReadOnly = $false } }
        Remove-Item -Path "$Destination\*" -Recurse -Force -ErrorAction Stop
    }
}

if ($Apply) {
    # ----- Mount ISO -----
    Write-Log "Mounting ISO"
    $mount = Mount-DiskImage -ImagePath $ISOFile -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 2   # Allow drive letter assignment
    $drive = ($mount | Get-Volume).DriveLetter
    if (-not $drive) {
        Dismount-DiskImage -ImagePath $ISOFile -ErrorAction SilentlyContinue | Out-Null
        throw "Failed to obtain drive letter for mounted ISO."
    }
    $sourceRoot = "${drive}:"
    Write-Log "ISO mounted at $sourceRoot" 'OK'

    try {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        Write-Log "Copying ISO contents via robocopy (3-10 minutes)"
        $rcArgs = @($sourceRoot, $Destination,
                    "/E", "/Z", "/R:1", "/W:5",
                    "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/NP")
        & robocopy @rcArgs | Out-Null
        $rcExit = $LASTEXITCODE
        if ($rcExit -ge 8) {
            throw "robocopy failed with exit code $rcExit"
        }
        Write-Log "Copy complete (robocopy exit $rcExit)" 'OK'

    } finally {
        Write-Log "Dismounting ISO"
        Dismount-DiskImage -ImagePath $ISOFile -ErrorAction SilentlyContinue | Out-Null
    }

    # ----- Clear read-only attribute on all files -----
    Write-Log "Clearing read-only attribute on all extracted files"
    $cleared = 0
    Get-ChildItem -Path $Destination -Recurse -Force -File | ForEach-Object {
        if ($_.IsReadOnly) {
            $_.IsReadOnly = $false
            $cleared++
        }
    }
    Write-Log "Cleared read-only on $cleared file(s)" 'OK'

    # ----- Verify install.wim -----
    $wim = Join-Path $Destination "sources\install.wim"
    if (Test-Path $wim) {
        $wimItem = Get-Item $wim
        $sizeGB  = [math]::Round($wimItem.Length / 1GB, 2)
        Write-Log "install.wim present at $wim (Size: $sizeGB GB, IsReadOnly: $($wimItem.IsReadOnly))" 'OK'
        if ($wimItem.IsReadOnly) {
            Write-Log "install.wim still read-only - Phase 03 will fail" 'ERROR'
        }
    } else {
        Write-Log "install.wim NOT found at $wim" 'ERROR'
    }

    # ----- Enumerate editions -----
    Write-Log ""
    Write-Log "Available editions in install.wim:"
    Get-WindowsImage -ImagePath $wim | ForEach-Object {
        Write-Log "  Index $($_.ImageIndex): $($_.ImageName)"
    }

    Write-Log ""
    Write-Log "===================================="
    Write-Log "Phase 01 complete. Source: $Destination" 'OK'
    Write-Log "Reminder: 04-Remove-ProvisionedApps.ps1 needs `$WimPath and `$Index set"
    Write-Log "  (use the Enterprise index from the edition list above)."
    Write-Log "Next: run 03-Initialize-BuildEnvironment.ps1" 'NEXT'
    Write-Log "===================================="
} else {
    Write-Log "DRY-RUN complete. Set `$Apply = `$true to execute." 'OK'
}
