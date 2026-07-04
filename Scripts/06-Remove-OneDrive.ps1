# =============================================================================
# Windows 11 Image Build - Script 04: Offline OneDriveSetup Removal
# -----------------------------------------------------------------------------
# Reference: WIN11-GOLDIMG-001, Section 3.1.3
# Owner: IT Solutions Architecture
#
# Removes built-in OneDriveSetup.exe from the mounted Windows image.
# OneDrive is NOT a provisioned AppX - it's a per-user MSI invoked at first
# logon from System32/SysWOW64. Therefore Remove-AppxProvisionedPackage
# cannot remove it; this script handles the file + registry cleanup.
#
# Why: ORG corporate M365 OneDrive for Business is deployed separately;
# leaving the OOBE version causes personal-account prompts and double-icons.
#
# Prerequisite: WIM is currently mounted at $MountPath (by script 03).
#
# Run as Administrator. Set $Apply = $true to execute (default: dry-run).
# =============================================================================

$Apply       = $true
$MountPath   = "E:\WimMount"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath     = Join-Path $ProjectRoot "Logs\04-OneDriveRemoval-$(Get-Date -Format yyyyMMdd-HHmmss).log"

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

# ----- Guard: confirm WIM is actually mounted -----
if (-not (Test-Path $MountPath)) {
    throw "Mount path does not exist: $MountPath. Run 04-Remove-ProvisionedApps.ps1 first."
}
if (-not (Test-Path "$MountPath\Windows\System32")) {
    throw "Mount path does not look like a Windows image (missing System32). Run 04-Remove-ProvisionedApps.ps1 first."
}

$mountedHere = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -eq $MountPath }
if (-not $mountedHere) {
    Write-Log "WARNING: Get-WindowsImage -Mounted does not report a mount at $MountPath" 'WARN'
    Write-Log "Continuing - file system path exists, but registry hive operations may fail." 'WARN'
}

Write-Log "DRY-RUN MODE: $(-not $Apply)"
Write-Log "Mount: $MountPath"

# ----- Targets to remove from the offline image -----
$targets = @(
    "$MountPath\Windows\System32\OneDriveSetup.exe",
    "$MountPath\Windows\SysWOW64\OneDriveSetup.exe"
)

# ----- File removal -----
foreach ($target in $targets) {
    if (Test-Path $target) {
        Write-Log "Found: $target"
        if ($Apply) {
            try {
                takeown /F $target /A | Out-Null
                icacls $target /grant "BUILTIN\Administrators:F" | Out-Null
                Remove-Item -Path $target -Force -ErrorAction Stop
                Write-Log "  Removed: $target" 'OK'
            } catch {
                Write-Log "  FAIL: $target - $_" 'ERROR'
            }
        }
    } else {
        Write-Log "Not present: $target" 'SKIP'
    }
}

# ----- Offline registry cleanup -----
$offlineSoftwareHive = "$MountPath\Windows\System32\config\SOFTWARE"
$offlineHiveMount    = "HKLM\OFFLINE_SOFTWARE"

if (Test-Path $offlineSoftwareHive) {
    Write-Log "Loading offline SOFTWARE hive from $offlineSoftwareHive"
    if ($Apply) {
        try {
            $regResult = reg load $offlineHiveMount $offlineSoftwareHive 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "reg load failed: $regResult" 'ERROR'
            } else {
                Write-Log "Hive loaded at $offlineHiveMount" 'OK'

                $runKeyPath = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path $runKeyPath) {
                    $runValues = Get-ItemProperty -Path $runKeyPath -ErrorAction SilentlyContinue
                    if ($null -ne $runValues.OneDriveSetup) {
                        Remove-ItemProperty -Path $runKeyPath -Name 'OneDriveSetup' -ErrorAction Stop
                        Write-Log "Removed HKLM Run\OneDriveSetup value" 'OK'
                    } else {
                        Write-Log "No OneDriveSetup value in Run key" 'SKIP'
                    }
                }

                # =====================================================================
                # REINSTALL SUPPRESSION
                # ---------------------------------------------------------------------
                # Even after Remove-AppxProvisionedPackage, Windows can re-fetch
                # "suggested" and "consumer" apps via ContentDeliveryManager and
                # Cloud Content. These keys disable those mechanisms at the image
                # level so removed apps stay removed.
                # =====================================================================
                Write-Log ""
                Write-Log "Applying reinstall suppression in offline hive..."

                $suppressions = @(
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "ContentDeliveryAllowed"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "OemPreInstalledAppsEnabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "PreInstalledAppsEnabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "PreInstalledAppsEverEnabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "SilentInstalledAppsEnabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "SubscribedContent-338388Enabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "SubscribedContent-338389Enabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "SubscribedContent-353698Enabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                        Name  = "SystemPaneSuggestionsEnabled"
                        Type  = "DWord"
                        Value = 0
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                        Name  = "DisableWindowsConsumerFeatures"
                        Type  = "DWord"
                        Value = 1
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                        Name  = "DisableConsumerAccountStateContent"
                        Type  = "DWord"
                        Value = 1
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                        Name  = "DisableSoftLanding"
                        Type  = "DWord"
                        Value = 1
                    },
                    @{
                        Path  = "Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Policies\Microsoft\WindowsStore"
                        Name  = "AutoDownload"
                        Type  = "DWord"
                        Value = 2
                    }
                )

                $suppressed = 0
                $suppressFailed = 0
                foreach ($s in $suppressions) {
                    try {
                        if (-not (Test-Path $s.Path)) {
                            New-Item -Path $s.Path -Force | Out-Null
                        }
                        Set-ItemProperty -Path $s.Path -Name $s.Name -Value $s.Value -Type $s.Type -ErrorAction Stop
                        Write-Log ("  OK     {0} = {1}" -f $s.Name, $s.Value) 'OK'
                        $suppressed++
                    } catch {
                        Write-Log ("  FAIL   {0} - {1}" -f $s.Name, $_.Exception.Message) 'ERROR'
                        $suppressFailed++
                    }
                }
                Write-Log ("Reinstall suppression: {0} applied, {1} failed" -f $suppressed, $suppressFailed) 'OK'

                [GC]::Collect()
                Start-Sleep -Seconds 2
                reg unload $offlineHiveMount 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Hive unloaded" 'OK'
                } else {
                    Write-Log "Hive unload failed - try manually: reg unload $offlineHiveMount" 'WARN'
                }
            }
        } catch {
            Write-Log "Registry cleanup exception: $_" 'ERROR'
            reg unload $offlineHiveMount 2>&1 | Out-Null
        }
    }
} else {
    Write-Log "Offline SOFTWARE hive not found at $offlineSoftwareHive" 'WARN'
}

# ----- Summary -----
if ($Apply) {
    Write-Log ""
    Write-Log "===================================="
    Write-Log "Phase 04 complete. WIM still mounted at $MountPath" 'OK'
    Write-Log "Next: run 07-Enable-DotNet35.ps1" 'NEXT'
    Write-Log "===================================="
} else {
    Write-Log "DRY-RUN complete. Set `$Apply = `$true to execute." 'OK'
}
