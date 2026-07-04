# OEM-Template\

Source files that get packed into the install media's `sources\$OEM$\` folder
during Phase 1.7. Windows Setup copies them to the target machine during install,
without any Sysprep or post-install scripting.

## Contents

| File | Destination on target machine | Purpose |
|---|---|---|
| `SetupComplete.cmd` | `C:\Windows\Setup\Scripts\SetupComplete.cmd` | Runs as SYSTEM at end of Setup |
| `OEMLogo.bmp` (optional) | `C:\Windows\System32\OEMLogo.bmp` | Logo shown in Settings → About (max 120×120 px) |

## What `SetupComplete.cmd` does

| Task | Effect |
|---|---|
| **1. DevicePath registry** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DevicePath = %SystemRoot%\inf;C:\Drivers` — tells PnP to look in `C:\Drivers` for .inf files |
| **2. Default wallpaper** | Writes wallpaper path to `HKU\.DEFAULT\Control Panel\Desktop\Wallpaper` AND to `C:\Users\Default\NTUSER.DAT` so new users see Wallpaper.jpg at first logon |
| **3. Lock screen** | Sets `HKLM\...\PersonalizationCSP\LockScreenImagePath` to LockScreen.jpg |
| **4. OEM Information** | Populates `HKLM\...\OEMInformation` with ORG manufacturer, support phone, hours, URL, provider, logo |

## How `SetupComplete.cmd` is triggered

Windows Setup automatically looks for a script at:
```
%WINDIR%\Setup\Scripts\SetupComplete.cmd
```
If present, Setup runs it **as SYSTEM, before OOBE, before first user logon**, and waits for it to complete (timeout: 1 hour). No unattend.xml entry is required to trigger this — it's a built-in Setup feature.

## Placeholders to fill before production

In `SetupComplete.cmd` Task 4 — search for `<SERVICE_DESK_PHONE>` and replace with the actual ORG IT Service Desk phone number. Verify the support URL is still correct.

## OEMLogo.bmp specifications

If you want a logo in Settings → About:

- Format: **24-bit .bmp** (BMP, not PNG/JPG)
- Dimensions: **maximum 120×120 pixels** (smaller is fine, square recommended)
- Filename: must be exactly `OEMLogo.bmp`
- Place it at `OEM-Template\OEMLogo.bmp` — Phase 1.7 will copy it to `$OEM$\$$\System32\OEMLogo.bmp` so it lands at `C:\Windows\System32\OEMLogo.bmp`

If no `OEMLogo.bmp` is present, `SetupComplete.cmd` logs an INFO message and Settings → About shows no logo.

## Editing rules

- Keep `SetupComplete.cmd` **idempotent** — Setup can re-run it on repair scenarios
- Always log to `%WINDIR%\Setup\Scripts\SetupComplete.log`
- Do NOT block on user interaction (no `pause`, no `runas`, no GUI prompts)
- Do NOT take longer than ~10 minutes; Setup times out at 1 hour but UX suffers
- Any change requires RFC + IT Architecture approval (this is privileged SYSTEM code running pre-logon)
