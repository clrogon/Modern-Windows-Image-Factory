#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Re-apply G7 post-install customization tasks
    Runs on the reference VM in audit mode.

.DESCRIPTION
    Re-applies the customization tasks that SetupComplete.cmd was supposed
    to perform during install. Useful when:

      1. SetupComplete.cmd failed silently on the reference VM
         (e.g., wallpaper / lockscreen / OEM logo not visible after install)
      2. Validating corrected SetupComplete.cmd logic without rebuilding ISO
      3. Re-applying customization after manual changes mid-build cycle

    This is NOT a replacement for SetupComplete.cmd. The production path is
    still: ISO -> install -> SetupComplete.cmd -> Sysprep.

    This script exists for diagnostic / repair scenarios only.

.PARAMETER Apply
    Default $false (dry-run). Set $true to execute.

.PARAMETER NetFx3SourcePath
    Path to sources\sxs (mount the original ISO and supply <drive>:\sources\sxs)
    Default: D:\sources\sxs

.NOTES
    Document : WIN11-GOLDIMG-001 v2.3
    Folder   : AuditMode\
    Phase    : Reference VM, audit mode, BEFORE Sysprep
    Order    : Apply-SecurityBaseline.ps1 FIRST, then this if needed

    Tasks mirrored from SetupComplete.cmd v2.3:
      1. DevicePath + pnputil scan
      2. Default user hive (wallpaper / locale / GeoID / CMTrace EULA)
      3. Lock screen via PersonalizationCSP
      4. OEM Information
      5. CMTrace ProgID + .log association
      6. Timezone (target market: Angola - W. Central Africa Standard Time)
      7. Machine GeoID (target market: Angola = 9)
      8. .NET Framework 3.5 (online, only if not already enabled)
#>

[CmdletBinding()]
param(
    [bool]$Apply = $false,
    [string]$NetFx3SourcePath = 'D:\sources\sxs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration (target market: Angola) ---
$Timezone     = 'W. Central Africa Standard Time'   # Angola; change if deploying elsewhere
$GeoId        = 9                                   # Angola
$LocaleName   = 'pt-AO'                             # Portuguese (Angola); change if deploying elsewhere
$GeoName      = 'AO'                                # Angola
$BrandRoot    = 'C:\Windows\Web\Wallpaper\CompanyBrand'
$WallpaperFile  = "$BrandRoot\Wallpaper.jpg"
$LockScreenFile = "$BrandRoot\LockScreen.jpg"
$CMTracePath  = 'C:\Windows\System32\CMTrace.exe'
$OEMLogoPath  = 'C:\Windows\System32\OEMLogo.bmp'

$LogPath = 'C:\AuditMode\Logs'
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogPath "PostInstallCustomization-$Mode-$Timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $Line -ForegroundColor Red }
        'WARN'  { Write-Host $Line -ForegroundColor Yellow }
        'OK'    { Write-Host $Line -ForegroundColor Green }
        default { Write-Host $Line }
    }
}

Write-Log '========== Apply-PostInstallCustomization =========='
Write-Log "Mode: $Mode"

# ==========================================================================
# TASK 1 - DevicePath
# ==========================================================================
function Set-DevicePath {
    Write-Log ''
    Write-Log '----- Task 1: DevicePath -----'
    if ($Apply) {
        try {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion' `
                -Name 'DevicePath' -Value '%SystemRoot%\inf;C:\Drivers' -Type ExpandString -Force
            Write-Log 'DevicePath set to %SystemRoot%\inf;C:\Drivers' 'OK'

            if (Test-Path 'C:\Drivers') {
                & pnputil.exe /scan-devices | Out-Null
                Write-Log 'pnputil scan triggered' 'OK'
            } else {
                Write-Log 'C:\Drivers not present - skipping pnputil scan' 'WARN'
            }
        } catch {
            Write-Log "DevicePath set failed: $_" 'ERROR'
        }
    } else {
        Write-Log '[DRY-RUN] Would set DevicePath and trigger pnputil scan'
    }
}

# ==========================================================================
# TASK 2 - Default user hive (consolidated load/unload)
# ==========================================================================
function Set-DefaultUserHive {
    Write-Log ''
    Write-Log '----- Task 2: Default user hive (wallpaper / locale / geo / CMTrace EULA) -----'

    # --- .DEFAULT (SYSTEM profile / Welcome screen) ---
    if ($Apply) {
        try {
            if (Test-Path $WallpaperFile) {
                Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'Wallpaper'      -Value $WallpaperFile -Force
                Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10'           -Force
                Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'TileWallpaper'  -Value '0'            -Force
                Write-Log '.DEFAULT wallpaper applied' 'OK'
            } else {
                Write-Log "Wallpaper file missing: $WallpaperFile" 'WARN'
            }

            Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International' -Name 'LocaleName' -Value $LocaleName -Force
            $GeoKey = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International\Geo'
            if (-not (Test-Path $GeoKey)) { New-Item -Path $GeoKey -Force | Out-Null }
            Set-ItemProperty -Path $GeoKey -Name 'Nation' -Value "$GeoId"   -Force
            Set-ItemProperty -Path $GeoKey -Name 'Name'   -Value $GeoName -Force
            Write-Log '.DEFAULT locale and geo applied' 'OK'
        } catch {
            Write-Log ".DEFAULT operations failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would write wallpaper / locale / geo to HKU\.DEFAULT"
    }

    # --- Default user NTUSER.DAT ---
    $DefaultHive = 'C:\Users\Default\NTUSER.DAT'
    if (-not (Test-Path $DefaultHive)) {
        Write-Log "Default user hive missing: $DefaultHive" 'ERROR'
        return
    }

    if ($Apply) {
        try {
            & reg.exe load 'HKU\DefaultUserHive' $DefaultHive | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "reg load failed: exit $LASTEXITCODE" 'ERROR'
                return
            }
            Write-Log 'Loaded Default user NTUSER.DAT as HKU\DefaultUserHive' 'OK'

            # Wallpaper
            if (Test-Path $WallpaperFile) {
                Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUserHive\Control Panel\Desktop' -Name 'Wallpaper'      -Value $WallpaperFile -Force
                Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUserHive\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10'           -Force
                Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUserHive\Control Panel\Desktop' -Name 'TileWallpaper'  -Value '0'            -Force
            }

            # CMTrace EULA suppression
            $TraceKey = 'Registry::HKEY_USERS\DefaultUserHive\SOFTWARE\Microsoft\Trace32'
            if (-not (Test-Path $TraceKey)) { New-Item -Path $TraceKey -Force | Out-Null }
            Set-ItemProperty -Path $TraceKey -Name 'Register File Types' -Value 0 -Type DWord -Force

            # Locale + Geo
            Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUserHive\Control Panel\International' -Name 'LocaleName' -Value $LocaleName -Force
            $GeoKey = 'Registry::HKEY_USERS\DefaultUserHive\Control Panel\International\Geo'
            if (-not (Test-Path $GeoKey)) { New-Item -Path $GeoKey -Force | Out-Null }
            Set-ItemProperty -Path $GeoKey -Name 'Nation' -Value "$GeoId" -Force
            Set-ItemProperty -Path $GeoKey -Name 'Name'   -Value $GeoName -Force

            Write-Log 'Default user hive populated' 'OK'

            # Release handles before unload
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500

            & reg.exe unload 'HKU\DefaultUserHive' | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log 'First unload attempt failed, retrying after 2s' 'WARN'
                Start-Sleep -Seconds 2
                & reg.exe unload 'HKU\DefaultUserHive' | Out-Null
            }
            Write-Log 'Default user NTUSER.DAT unloaded' 'OK'
        } catch {
            Write-Log "Default user hive ops failed: $_" 'ERROR'
            # Best effort to unload even on error
            & reg.exe unload 'HKU\DefaultUserHive' 2>$null | Out-Null
        }
    } else {
        Write-Log "[DRY-RUN] Would load Default NTUSER.DAT, write wallpaper / locale / geo / CMTrace EULA, unload"
    }
}

# ==========================================================================
# TASK 3 - Lock screen
# ==========================================================================
function Set-LockScreen {
    Write-Log ''
    Write-Log '----- Task 3: Lock screen via PersonalizationCSP -----'
    if (-not (Test-Path $LockScreenFile)) {
        Write-Log "Lock screen file missing: $LockScreenFile" 'ERROR'
        return
    }
    if ($Apply) {
        try {
            $Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
            if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
            Set-ItemProperty -Path $Key -Name 'LockScreenImagePath'   -Value $LockScreenFile -Type String -Force
            Set-ItemProperty -Path $Key -Name 'LockScreenImageUrl'    -Value $LockScreenFile -Type String -Force
            Set-ItemProperty -Path $Key -Name 'LockScreenImageStatus' -Value 1               -Type DWord  -Force
            Write-Log 'PersonalizationCSP lock screen keys applied' 'OK'
        } catch {
            Write-Log "Lock screen apply failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would set PersonalizationCSP keys for lock screen"
    }
}

# ==========================================================================
# TASK 4 - OEM Information
# ==========================================================================
function Set-OEMInformation {
    Write-Log ''
    Write-Log '----- Task 4: OEM Information -----'
    $Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    $Values = @{
        Manufacturer    = 'Contoso Corp Ltd.'
        Model           = 'ORG Corporate Workstation'
        SupportPhone    = '<SERVICE_DESK_PHONE>'
        SupportHours    = '<SERVICE_DESK_HOURS>'
        SupportProvider = 'ORG IT Service Desk'
        SupportURL      = 'https://contoso.sharepoint.com/sites/it/servicedesk'
    }
    if ($Apply) {
        try {
            if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
            foreach ($k in $Values.Keys) {
                Set-ItemProperty -Path $Key -Name $k -Value $Values[$k] -Type String -Force
            }
            if (Test-Path $OEMLogoPath) {
                Set-ItemProperty -Path $Key -Name 'Logo' -Value $OEMLogoPath -Type String -Force
                Write-Log "OEM logo registered: $OEMLogoPath" 'OK'
            } else {
                Write-Log "OEMLogo.bmp not present at $OEMLogoPath - logo skipped" 'WARN'
            }
            Write-Log 'OEM Information applied' 'OK'
        } catch {
            Write-Log "OEM Information apply failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would set OEM Information keys"
    }
}

# ==========================================================================
# TASK 5 - CMTrace registration
# ==========================================================================
function Register-CMTrace {
    Write-Log ''
    Write-Log '----- Task 5: CMTrace ProgID + .log association -----'
    if (-not (Test-Path $CMTracePath)) {
        Write-Log "CMTrace.exe not at $CMTracePath - skipping" 'WARN'
        return
    }
    if ($Apply) {
        try {
            $ProgId = 'HKLM:\SOFTWARE\Classes\CMTrace.LogFile'
            if (-not (Test-Path $ProgId)) { New-Item -Path $ProgId -Force | Out-Null }
            Set-ItemProperty -Path $ProgId -Name '(Default)' -Value 'Configuration Manager Trace Log' -Force

            $IconKey = "$ProgId\DefaultIcon"
            if (-not (Test-Path $IconKey)) { New-Item -Path $IconKey -Force | Out-Null }
            Set-ItemProperty -Path $IconKey -Name '(Default)' -Value "$CMTracePath,0" -Force

            $CmdKey = "$ProgId\shell\open\command"
            if (-not (Test-Path $CmdKey)) { New-Item -Path $CmdKey -Force | Out-Null }
            Set-ItemProperty -Path $CmdKey -Name '(Default)' -Value "`"$CMTracePath`" `"%1`"" -Force

            $Ext = 'HKLM:\SOFTWARE\Classes\.log'
            if (-not (Test-Path $Ext)) { New-Item -Path $Ext -Force | Out-Null }
            Set-ItemProperty -Path $Ext -Name 'Content Type' -Value 'text/plain' -Force

            $OpenWith = "$Ext\OpenWithProgids"
            if (-not (Test-Path $OpenWith)) { New-Item -Path $OpenWith -Force | Out-Null }
            New-ItemProperty -Path $OpenWith -Name 'CMTrace.LogFile' -PropertyType None -Force | Out-Null

            Write-Log 'CMTrace ProgID and .log association registered' 'OK'
        } catch {
            Write-Log "CMTrace registration failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would register CMTrace ProgID and .log association"
    }
}

# ==========================================================================
# TASK 6 - Timezone
# ==========================================================================
function Set-DefaultTimezone {
    Write-Log ''
    Write-Log '----- Task 6: Timezone -----'
    if ($Apply) {
        try {
            & tzutil.exe /s $Timezone
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Timezone set to: $Timezone" 'OK'
                $current = & tzutil.exe /g
                Write-Log "tzutil /g reports: $current"
            } else {
                Write-Log "tzutil /s exit $LASTEXITCODE" 'ERROR'
            }
        } catch {
            Write-Log "Timezone set failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would run: tzutil /s `"$Timezone`""
    }
}

# ==========================================================================
# TASK 7 - Machine GeoID
# ==========================================================================
function Set-MachineGeo {
    Write-Log ''
    Write-Log '----- Task 7: Machine GeoID -----'
    if ($Apply) {
        try {
            Set-WinHomeLocation -GeoId $GeoId -ErrorAction Stop
            Write-Log "Machine GeoID set to $GeoId" 'OK'
        } catch {
            Write-Log "Set-WinHomeLocation failed: $_" 'WARN'
            Write-Log 'Falling back to direct registry write under HKCU' 'WARN'
            $GeoKey = 'HKCU:\Control Panel\International\Geo'
            if (-not (Test-Path $GeoKey)) { New-Item -Path $GeoKey -Force | Out-Null }
            Set-ItemProperty -Path $GeoKey -Name 'Nation' -Value "$GeoId" -Force
            Set-ItemProperty -Path $GeoKey -Name 'Name'   -Value $GeoName -Force
        }
    } else {
        Write-Log "[DRY-RUN] Would run: Set-WinHomeLocation -GeoId $GeoId"
    }
}

# ==========================================================================
# TASK 8 - .NET Framework 3.5
# ==========================================================================
function Enable-NetFx3 {
    Write-Log ''
    Write-Log '----- Task 8: .NET Framework 3.5 -----'

    $Feature = Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -ErrorAction SilentlyContinue
    if ($Feature -and $Feature.State -eq 'Enabled') {
        Write-Log 'NetFx3 already enabled' 'OK'
        return
    }

    if (-not (Test-Path $NetFx3SourcePath)) {
        Write-Log "NetFx3 source not found at $NetFx3SourcePath" 'WARN'
        Write-Log 'Mount the Win11 ISO and supply -NetFx3SourcePath <drive>:\sources\sxs' 'WARN'
        return
    }

    if ($Apply) {
        try {
            $DismOut = & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:$NetFx3SourcePath 2>&1
            $DismOut | ForEach-Object { Write-Log "  $_" }
            if ($LASTEXITCODE -ne 0) {
                Write-Log "DISM exited with code $LASTEXITCODE" 'ERROR'
            } else {
                Write-Log 'NetFx3 enabled' 'OK'
            }
        } catch {
            Write-Log "NetFx3 enable failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would run: dism /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:$NetFx3SourcePath"
    }
}

# --- Run all tasks ---
try {
    Set-DevicePath
    Set-DefaultUserHive
    Set-LockScreen
    Set-OEMInformation
    Register-CMTrace
    Set-DefaultTimezone
    Set-MachineGeo
    Enable-NetFx3

    Write-Log ''
    Write-Log "========== Done. Log: $LogFile =========="

    if (-not $Apply) {
        Write-Log ''
        Write-Log '*** DRY-RUN - no changes made. Re-run with -Apply $true ***' 'WARN'
    } else {
        Write-Log ''
        Write-Log '*** Customization re-applied. Confirm visually before Sysprep:' 'OK'
        Write-Log '***   - Log off / log on as a fresh user to see Default user inheritance'
        Write-Log '***   - Settings > About > shows ORG OEM Information'
        Write-Log '***   - Lock screen shows LockScreen.jpg'
        Write-Log '***   - .log files open in CMTrace'
    }
} catch {
    Write-Log "UNHANDLED ERROR: $_" 'ERROR'
    Write-Log $_.ScriptStackTrace 'ERROR'
    exit 1
}
