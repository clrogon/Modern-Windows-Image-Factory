# =============================================================================
# Windows 11 Image Build - Script 05: Dismount and Commit WIM
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Section 3.1.3
# Owner: IT Solutions Architecture
#
# Dismounts the mounted WIM and SAVES the changes (apps removed in script 03,
# OneDrive removed in script 04). Separated into its own script so the
# operator has a clear commit gate.
#
# Run as Administrator. Pass -Apply to execute (default: dry-run).
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Apply
)

$MountPath   = "E:\WimMount"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\DismountImage-$(Get-Date -Format yyyyMMdd-HHmmss).log"

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

$mountedHere = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -eq $MountPath }

if (-not $mountedHere) {
    Write-Log "No image is mounted at $MountPath" 'WARN'
    Write-Log "Nothing to dismount. Confirm scripts 03 and 04 actually ran with `$Apply = `$true."
    return
}

Write-Log "Mounted image:"
Write-Log "  Path:       $($mountedHere.Path)"
Write-Log "  ImagePath:  $($mountedHere.ImagePath)"
Write-Log "  Status:     $($mountedHere.MountStatus)"
Write-Log "  ImageIndex: $($mountedHere.ImageIndex)"

if ($Apply) {
    Write-Log ""
    Write-Log "Dismounting and COMMITTING changes (this may take several minutes)"
    try {
        Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop
        Write-Log "Dismount complete - changes committed to $($mountedHere.ImagePath)" 'OK'
    } catch {
        Write-Log "Dismount FAILED: $_" 'ERROR'
        Write-Log "Try manual recovery:"
        Write-Log "  Dismount-WindowsImage -Path '$MountPath' -Discard  (loses changes)"
        Write-Log "  OR"
        Write-Log "  Clear-WindowsCorruptMountPoint                       (force-clear stuck mount)"
        throw
    }
} else {
    Write-Log "DRY-RUN: would run: Dismount-WindowsImage -Path '$MountPath' -Save" 'INFO'
    Write-Log "Set `$Apply = `$true to execute." 'INFO'
    return
}

Write-Log ""
Write-Log "===================================="
Write-Log "Phase 05 complete." 'OK'
Write-Log "Next: run 10-Build-OemLayer.ps1" 'NEXT'
Write-Log "Then: 11-Build-Iso.ps1 (repackage bootable ISO)"
Write-Log "===================================="
