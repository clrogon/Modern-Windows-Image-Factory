#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Emergency fix for current reference VM
    Re-applies G7 tasks 2/3/4 (wallpaper, lock screen, OEM info) on a VM
    where SetupComplete.cmd failed to apply them.

.DESCRIPTION
    Run on the reference VM in audit mode, AFTER installing from the
    current (broken-SetupComplete) ISO. Lets you validate corrected
    logic before rebuilding the ISO.

    Also handles CMTrace registration and .NET 3.5 enablement online
    if those weren't baked in.

.PARAMETER Apply
    Default $false. Set $true to execute.

.PARAMETER NetFx3SourcePath
    Path to sources\sxs (mount the original ISO, or supply E:\sources\sxs)
    Default: D:\sources\sxs

.NOTES
    This is a hotfix only. Production builds MUST be rebuilt with the
    corrected SetupComplete.cmd. This script does not replace the build.
#>

[CmdletBinding()]
param(
    [bool]$Apply = $false,
    [string]$NetFx3SourcePath = 'D:\sources\sxs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogPath = 'C:\AuditMode\Logs'
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $LogPath "FixCurrentVM-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

Write-Log '========== Emergency VM Fix =========='
Write-Log "Apply: $Apply"

# --- Locate branding files (they were copied via $OEM$) ---
$WallpaperCandidates = @(
    'c:\Windows\Web\Wallpaper\CompanyBrand\Wallpaper.jpg'
)
$LockScreenCandidates = @(
    'c:\Windows\Web\Wallpaper\CompanyBrand\LockScreen.jpg'
)

$Wallpaper  = $WallpaperCandidates  | Where-Object { Test-Path $_ } | Select-Object -First 1
$LockScreen = $LockScreenCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $Wallpaper)  { Write-Log "Wallpaper file not found in any candidate path" 'ERROR' }
else                  { Write-Log "Wallpaper:  $Wallpaper" }
if (-not $LockScreen) { Write-Log "Lock screen file not found in any candidate path" 'ERROR' }
else                  { Write-Log "Lock screen: $LockScreen" }

# ==========================================================================
# FIX 1 - Wallpaper to .DEFAULT + Default user
# ==========================================================================
function Set-DefaultWallpaper {
    if (-not $Wallpaper) { Write-Log 'Skip wallpaper - file missing' 'WARN'; return }
    Write-Log '--- Wallpaper ---'

    if ($Apply) {
        try {
            # .DEFAULT hive
            Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'Wallpaper' -Value $Wallpaper -Force
            Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force
            Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Force
            Write-Log '.DEFAULT hive updated' 'OK'

            # Default user NTUSER.DAT
            $DefaultHive = 'C:\Users\Default\NTUSER.DAT'
            & reg.exe load 'HKU\DefaultUser' $DefaultHive 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "reg load failed: $LASTEXITCODE" }

            Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop' -Name 'Wallpaper' -Value $Wallpaper -Force
            Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force
            Set-ItemProperty -Path 'Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Force

            [gc]::Collect(); Start-Sleep -Milliseconds 500
            & reg.exe unload 'HKU\DefaultUser' 2>&1 | Out-Null
            Write-Log 'Default user NTUSER.DAT updated' 'OK'
        } catch {
            Write-Log "Wallpaper apply failed: $_" 'ERROR'
        }
    } else {
        Write-Log "[DRY-RUN] Would set wallpaper to $Wallpaper in .DEFAULT and Default user hive"
    }
}

# ==========================================================================
# FIX 2 - Lock screen via PersonalizationCSP
# ==========================================================================
function Set-LockScreen {
    if (-not $LockScreen) { Write-Log 'Skip lock screen - file missing' 'WARN'; return }
    Write-Log '--- Lock screen ---'

    if ($Apply) {
        $Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
        Set-ItemProperty -Path $Key -Name 'LockScreenImagePath'   -Value $LockScreen -Type String -Force
        Set-ItemProperty -Path $Key -Name 'LockScreenImageUrl'    -Value $LockScreen -Type String -Force
        Set-ItemProperty -Path $Key -Name 'LockScreenImageStatus' -Value 1           -Type DWord  -Force
        Write-Log 'PersonalizationCSP keys set' 'OK'
    } else {
        Write-Log "[DRY-RUN] Would set PersonalizationCSP LockScreenImagePath/Url = $LockScreen"
    }
}

# ==========================================================================
# FIX 3 - OEM Information
# ==========================================================================
function Set-OEMInformation {
    Write-Log '--- OEM Information ---'
    $Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'

    $Values = @{
        Manufacturer    = 'Your Organization'
        Model           = 'ORG Corporate Workstation'
        SupportPhone    = '<SERVICE_DESK_PHONE>'
        SupportHours    = '<SERVICE_DESK_HOURS>'
        SupportURL      = 'https://contoso.sharepoint.com/sites/it/servicedesk'
        SupportProvider = 'ORG IT Service Desk'
    }

    if ($Apply) {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
        foreach ($k in $Values.Keys) {
            Set-ItemProperty -Path $Key -Name $k -Value $Values[$k] -Type String -Force
        }

        $LogoSrc = 'C:\Windows\System32\OEMLogo.bmp'
        if (Test-Path $LogoSrc) {
            Set-ItemProperty -Path $Key -Name 'Logo' -Value $LogoSrc -Type String -Force
            Write-Log "OEM logo registered: $LogoSrc" 'OK'
        } else {
            Write-Log "OEMLogo.bmp not present in System32 - logo skipped" 'WARN'
            Write-Log "If you have one, copy it to C:\Windows\System32\OEMLogo.bmp (24-bit BMP, max 120x120) and re-run" 'WARN'
        }
        Write-Log 'OEM Information applied' 'OK'
    } else {
        Write-Log "[DRY-RUN] Would set OEM Information keys (Manufacturer, Model, SupportPhone, etc.)"
    }
}

# ==========================================================================
# FIX 4 - CMTrace registration
# ==========================================================================
function Set-CMTraceAssociation {
    Write-Log '--- CMTrace registration ---'
    $CMTracePath = 'C:\Windows\System32\CMTrace.exe'

    if (-not (Test-Path $CMTracePath)) {
        Write-Log "CMTrace.exe not at $CMTracePath - copy it manually first, then re-run this fix" 'WARN'
        return
    }

    if ($Apply) {
        # ProgID
        $ProgId = 'HKLM:\SOFTWARE\Classes\CMTrace.LogFile'
        New-Item -Path $ProgId -Force | Out-Null
        Set-ItemProperty -Path $ProgId -Name '(Default)' -Value 'Configuration Manager Trace Log' -Force
        New-Item -Path "$ProgId\DefaultIcon" -Force | Out-Null
        Set-ItemProperty -Path "$ProgId\DefaultIcon" -Name '(Default)' -Value "$CMTracePath,0" -Force
        New-Item -Path "$ProgId\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "$ProgId\shell\open\command" -Name '(Default)' -Value "`"$CMTracePath`" `"%1`"" -Force

        # .log -> ProgID hint
        $Ext = 'HKLM:\SOFTWARE\Classes\.log'
        if (-not (Test-Path $Ext)) { New-Item -Path $Ext -Force | Out-Null }
        Set-ItemProperty -Path $Ext -Name 'Content Type' -Value 'text/plain' -Force
        $OpenWith = "$Ext\OpenWithProgids"
        if (-not (Test-Path $OpenWith)) { New-Item -Path $OpenWith -Force | Out-Null }
        New-ItemProperty -Path $OpenWith -Name 'CMTrace.LogFile' -PropertyType None -Force | Out-Null

        # Suppress CMTrace first-run EULA in .DEFAULT and Default user
        $TraceKey = 'Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Trace32'
        if (-not (Test-Path $TraceKey)) { New-Item -Path $TraceKey -Force | Out-Null }
        Set-ItemProperty -Path $TraceKey -Name 'Register File Types' -Value 0 -Type DWord -Force

        Write-Log 'CMTrace ProgID and association registered' 'OK'
        Write-Log 'NOTE: For new user profiles to inherit .log -> CMTrace, OEMDefaultAssociations.xml' 'INFO'
        Write-Log '      must exist in C:\Windows\System32\ AT THE TIME the user profile is created.' 'INFO'
    } else {
        Write-Log "[DRY-RUN] Would register CMTrace ProgID and .log association"
    }
}

# ==========================================================================
# FIX 5 - Enable .NET Framework 3.5
# ==========================================================================
function Enable-NetFx3 {
    Write-Log '--- .NET Framework 3.5 ---'

    $Feature = Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -ErrorAction SilentlyContinue
    if ($Feature -and $Feature.State -eq 'Enabled') {
        Write-Log 'NetFx3 already enabled, skipping' 'OK'
        return
    }

    if (-not (Test-Path $NetFx3SourcePath)) {
        Write-Log "NetFx3 source not found at $NetFx3SourcePath" 'ERROR'
        Write-Log 'Mount the Win11 ISO and point -NetFx3SourcePath at <drive>:\sources\sxs' 'ERROR'
        return
    }

    if ($Apply) {
        Write-Log "Enabling NetFx3 from $NetFx3SourcePath (this can take a few minutes)..."
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

# --- Run all fixes ---
Set-DefaultWallpaper
Set-LockScreen
Set-OEMInformation
Set-CMTraceAssociation
Enable-NetFx3

Write-Log ''
Write-Log "========== Done. Log: $LogFile =========="
if (-not $Apply) {
    Write-Log '*** DRY-RUN - no changes made. Re-run with -Apply $true ***' 'WARN'
}
