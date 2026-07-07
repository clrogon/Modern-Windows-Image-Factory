@echo off
REM =============================================================================
REM  Windows 11 Image Builder - SetupComplete.cmd
REM  Reference: WIN11-GOLDIMG-001
REM  Owner: IT Solutions Architecture
REM
REM  Runs as SYSTEM at the end of Windows Setup, BEFORE OOBE / first user logon.
REM  Delivered via $OEM$ at:  $OEM$\$$\Setup\Scripts\SetupComplete.cmd
REM                  lands at: C:\Windows\Setup\Scripts\SetupComplete.cmd
REM
REM  CONTRACT WITH SCRIPT 06:
REM    10-Build-OemLayer.ps1 must place the branding JPGs in the $OEM$ tree at
REM      $OEM$\$$\Web\Wallpaper\CompanyBrand\Wallpaper.jpg
REM      $OEM$\$$\Web\Wallpaper\CompanyBrand\LockScreen.jpg
REM    so they land at C:\Windows\Web\Wallpaper\CompanyBrand\ on the target (= %BRANDROOT%).
REM
REM  Tasks (in order):
REM    1. DevicePath -> PnP scans C:\Drivers for .inf, then pnputil /scan-devices
REM    2. Desktop wallpaper (changeable default): overwrite img0.jpg + Default hive
REM    3. Lock screen (enforced): disable Spotlight, then PersonalizationCSP
REM    4. OEM Information TEXT (no Logo - Win11 Settings does not render it)
REM    5. Sanity checks
REM    6. Remove C:\Drivers now that Task 1's PnP scan has bound whatever it found
REM       (also removes any non-.inf passenger files that rode along - .exe/.cab/
REM       .msi are not cleaned up by PnP and would otherwise sit on disk forever).
REM       NOTE: this also removes DevicePath's ability to serve a driver to NEW
REM       hardware attached later (e.g. a dock connected next month). If you need
REM       that, drop this task and keep C:\Drivers.
REM
REM  ASCII only. No smart quotes, no em-dashes.
REM =============================================================================

setlocal ENABLEEXTENSIONS

set "LOG=%SystemRoot%\Temp\SetupComplete.log"
set "BRANDROOT=%SystemRoot%\Web\Wallpaper\CompanyBrand"
set "DEFWALL=%SystemRoot%\Web\Wallpaper\Windows\img0.jpg"
set "WALLSRC=%BRANDROOT%\Wallpaper.jpg"
set "LOCKSRC=%BRANDROOT%\LockScreen.jpg"

REM --- IT Service Desk details: REPLACE before production -----------------------
set "OEM_MANUFACTURER=Contoso Corp Ltd."
set "OEM_MODEL=Standard Workstation"
set "OEM_SUPPORTPHONE=<SERVICE_DESK_PHONE>"
set "OEM_SUPPORTHOURS=<SERVICE_DESK_HOURS>"
set "OEM_SUPPORTURL=https://contoso.sharepoint.com/sites/it/servicedesk"
set "OEM_SUPPORTPROVIDER=ORG IT Service Desk"

echo ============================================================= > "%LOG%"
echo ORG SetupComplete.cmd v2.5 started : %DATE% %TIME%          >> "%LOG%"
echo ============================================================= >> "%LOG%"

REM =============================================================================
REM  TASK 1 - DevicePath for PnP driver search
REM =============================================================================
echo [TASK 1] Setting DevicePath and scanning for devices >> "%LOG%"

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion" /v DevicePath /t REG_EXPAND_SZ /d "%%SystemRoot%%\inf;C:\Drivers" /f >> "%LOG%" 2>&1
if %ERRORLEVEL% EQU 0 (echo [TASK 1] DevicePath set OK >> "%LOG%") else (echo [TASK 1] ERROR setting DevicePath >> "%LOG%")

if exist "C:\Drivers" (
    pnputil /scan-devices >> "%LOG%" 2>&1
    echo [TASK 1] pnputil /scan-devices triggered >> "%LOG%"
) else (
    echo [TASK 1] WARN - C:\Drivers not present, skipping scan >> "%LOG%"
)

REM =============================================================================
REM  TASK 2 - Desktop wallpaper (changeable corporate default)
REM           Method A: overwrite OS default img0.jpg  (primary, survives, changeable)
REM           Method B: set Default user hive value     (belt-and-suspenders)
REM =============================================================================
echo [TASK 2] Applying desktop wallpaper >> "%LOG%"

if not exist "%WALLSRC%" (
    echo [TASK 2] ERROR - wallpaper source missing: %WALLSRC% >> "%LOG%"
    goto :TASK3
)

REM --- Method A: take ownership of img0.jpg and overwrite it --------------------
takeown /f "%DEFWALL%" /a >> "%LOG%" 2>&1
icacls "%DEFWALL%" /grant *S-1-5-32-544:F >> "%LOG%" 2>&1
copy /y "%WALLSRC%" "%DEFWALL%" >> "%LOG%" 2>&1
if %ERRORLEVEL% EQU 0 (echo [TASK 2] img0.jpg overwritten OK >> "%LOG%") else (echo [TASK 2] ERROR overwriting img0.jpg >> "%LOG%")

REM --- Method B: set wallpaper in the Default profile hive ----------------------
REM  New user profiles are cloned from C:\Users\Default\NTUSER.DAT, NOT HKU\.DEFAULT.
reg load "HKLM\DEFAULTHIVE" "C:\Users\Default\NTUSER.DAT" >> "%LOG%" 2>&1
if %ERRORLEVEL% EQU 0 (
    reg add "HKLM\DEFAULTHIVE\Control Panel\Desktop" /v Wallpaper      /t REG_SZ /d "%DEFWALL%" /f >> "%LOG%" 2>&1
    reg add "HKLM\DEFAULTHIVE\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "10" /f       >> "%LOG%" 2>&1
    reg add "HKLM\DEFAULTHIVE\Control Panel\Desktop" /v TileWallpaper  /t REG_SZ /d "0"  /f        >> "%LOG%" 2>&1
    reg unload "HKLM\DEFAULTHIVE" >> "%LOG%" 2>&1
    echo [TASK 2] Default profile hive wallpaper set OK >> "%LOG%"
) else (
    echo [TASK 2] WARN - could not load Default NTUSER.DAT, skipped hive method >> "%LOG%"
)

:TASK3
REM =============================================================================
REM  TASK 3 - Lock screen (enforced via PersonalizationCSP)
REM           Step 1: disable Windows Spotlight (else it overrides static image)
REM           Step 2: point PersonalizationCSP at the staged image
REM =============================================================================
echo [TASK 3] Applying lock screen >> "%LOG%"

if not exist "%LOCKSRC%" (
    echo [TASK 3] ERROR - lock screen source missing: %LOCKSRC% >> "%LOG%"
    goto :TASK4
)

REM --- Step 1: disable Spotlight (Enterprise/Education) -------------------------
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsSpotlightFeatures /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableThirdPartySuggestions    /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
echo [TASK 3] Windows Spotlight disabled >> "%LOG%"

REM --- Step 2: PersonalizationCSP static lock screen ---------------------------
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" /v LockScreenImagePath   /t REG_SZ    /d "%LOCKSRC%" /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" /v LockScreenImageUrl    /t REG_SZ    /d "%LOCKSRC%" /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" /v LockScreenImageStatus /t REG_DWORD /d 1           /f >> "%LOG%" 2>&1
if %ERRORLEVEL% EQU 0 (echo [TASK 3] Lock screen set OK >> "%LOG%") else (echo [TASK 3] ERROR setting lock screen >> "%LOG%")

:TASK4
REM =============================================================================
REM  TASK 4 - OEM Information (TEXT ONLY - no Logo)
REM           Win11 Settings > About surfaces the support text fields but does
REM           NOT reliably render the legacy OEMInformation\Logo bitmap.
REM =============================================================================
echo [TASK 4] Writing OEM Information (text only) >> "%LOG%"

set "OEMKEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
reg add "%OEMKEY%" /v Manufacturer    /t REG_SZ /d "%OEM_MANUFACTURER%"    /f >> "%LOG%" 2>&1
reg add "%OEMKEY%" /v Model           /t REG_SZ /d "%OEM_MODEL%"           /f >> "%LOG%" 2>&1
reg add "%OEMKEY%" /v SupportPhone    /t REG_SZ /d "%OEM_SUPPORTPHONE%"    /f >> "%LOG%" 2>&1
reg add "%OEMKEY%" /v SupportHours    /t REG_SZ /d "%OEM_SUPPORTHOURS%"    /f >> "%LOG%" 2>&1
reg add "%OEMKEY%" /v SupportURL      /t REG_SZ /d "%OEM_SUPPORTURL%"      /f >> "%LOG%" 2>&1
reg add "%OEMKEY%" /v SupportProvider /t REG_SZ /d "%OEM_SUPPORTPROVIDER%" /f >> "%LOG%" 2>&1
REM  Logo intentionally NOT set (retired in v2.4 - did not render on Win11).
reg delete "%OEMKEY%" /v Logo /f >> "%LOG%" 2>&1
echo [TASK 4] OEM Information written (Logo retired) >> "%LOG%"

REM =============================================================================
REM  TASK 5 - Sanity checks
REM =============================================================================
echo [TASK 5] Sanity checks >> "%LOG%"

if exist "%DEFWALL%"  (echo [TASK 5] Wallpaper file present   >> "%LOG%") else (echo [TASK 5] WARN - wallpaper file missing   >> "%LOG%")
if exist "%LOCKSRC%"  (echo [TASK 5] Lock screen file present >> "%LOG%") else (echo [TASK 5] WARN - lock screen file missing >> "%LOG%")

if exist "C:\Drivers" (
    for /f %%i in ('dir /b /s "C:\Drivers\*.inf" 2^>nul ^| find /c /v ""') do echo [TASK 5] Driver INF count : %%i >> "%LOG%"
) else (
    echo [TASK 5] WARN - C:\Drivers missing >> "%LOG%"
)

tzutil /g >> "%LOG%" 2>&1

REM =============================================================================
REM  TASK 6 - Remove C:\Drivers now that PnP (Task 1) has bound whatever it found
REM =============================================================================
echo [TASK 6] Cleaning up C:\Drivers after PnP binding >> "%LOG%"

if exist "C:\Drivers" (
    rmdir /s /q "C:\Drivers" >> "%LOG%" 2>&1
    if exist "C:\Drivers" (
        echo [TASK 6] WARN - C:\Drivers still present after cleanup attempt >> "%LOG%"
    ) else (
        echo [TASK 6] C:\Drivers removed OK >> "%LOG%"
    )
) else (
    echo [TASK 6] C:\Drivers not present, nothing to clean up >> "%LOG%"
)

echo. >> "%LOG%"
echo ============================================================= >> "%LOG%"
echo ORG SetupComplete.cmd v2.5 finished : %DATE% %TIME%         >> "%LOG%"
echo ============================================================= >> "%LOG%"

endlocal
exit /b 0
