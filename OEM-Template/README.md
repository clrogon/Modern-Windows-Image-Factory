# OEM-Template\

Source files that get packed into the install media's `sources\$OEM$\` folder
during Phase 1.7. Windows Setup copies them to the target machine during install,
without any Sysprep or post-install scripting.

## Contents

| File | Destination on target machine | Purpose |
|---|---|---|
| `SetupComplete.cmd` | `C:\Windows\Setup\Scripts\SetupComplete.cmd` | Runs as SYSTEM at end of Setup |
| `CMTrace.exe` | `C:\Windows\System32\CMTrace.exe` | Staged by script `10`; `SetupComplete.cmd` skips CMTrace registration at runtime if not present |
| `Autounattend.xml` | ISO root | Staged by script `11`; answers Setup prompts, enters audit mode automatically |

`OEMLogo.bmp` is **not** part of this folder's contents as of v2.4 — see
[OEM logo - retired](#oem-logo---retired-in-v24) below.

## What `SetupComplete.cmd` does

| Task | Effect |
|---|---|
| **1. DevicePath registry** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DevicePath = %SystemRoot%\inf;C:\Drivers` — tells PnP to look in `C:\Drivers` for .inf files |
| **2. Default wallpaper** | Overwrites the real OS default (`%SystemRoot%\Web\Wallpaper\Windows\img0.jpg`) AND writes `Wallpaper`/`WallpaperStyle`/`TileWallpaper` to `C:\Users\Default\NTUSER.DAT` so new users see `Wallpaper.jpg` at first logon |
| **3. Lock screen** | Disables Windows Spotlight, then sets `HKLM\...\PersonalizationCSP\LockScreenImagePath`/`LockScreenImageUrl`/`LockScreenImageStatus` to `LockScreen.jpg` |
| **4. OEM Information** | Populates `HKLM\...\OEMInformation` with manufacturer, model, support phone/hours/URL/provider **text fields only** — no logo (see below) |
| **5. Sanity checks** | Logs whether the wallpaper/lock-screen files and `C:\Drivers` were actually present, and the current `.inf` count |
| **6. Remove `C:\Drivers`** | Deletes the staged driver tree (v2.5+) now that Task 1's PnP scan has bound whatever it found — otherwise its full contents (`.inf`, plus any `.exe`/`.cab`/`.msi` passengers that rode along) would sit on every deployed machine forever. Trade-off: this also removes `DevicePath`'s ability to serve a driver to hardware attached *after* first boot (e.g. a dock connected next month) — if you need that, drop Task 6 and keep `C:\Drivers`. |

## How `SetupComplete.cmd` is triggered

Windows Setup automatically looks for a script at:
```
%WINDIR%\Setup\Scripts\SetupComplete.cmd
```
If present, Setup runs it **as SYSTEM, before OOBE, before first user logon**, and waits for it to complete (timeout: 1 hour). No unattend.xml entry is required to trigger this — it's a built-in Setup feature.

## Placeholders to fill before production

In `SetupComplete.cmd` Task 4 — search for `<SERVICE_DESK_PHONE>` and replace with the actual ORG IT Service Desk phone number. Verify the support URL is still correct.

## OEM logo - retired in v2.4

Do not add an `OEMLogo.bmp` file here — it is not staged, not referenced, and will not
appear anywhere. This was confirmed by observation on a real deployed build: the classic
`OEMInformation\Logo` registry value is a legacy Control Panel feature that Win11's
modern `Settings > About` page does not render, even when correctly set. `SetupComplete.cmd`
Task 4 actively deletes any stale `Logo` value it finds and writes text fields only
(Manufacturer, Model, SupportPhone, SupportHours, SupportURL, SupportProvider) — those
text fields **do** render correctly in `Settings > About` and are the only OEM branding
surface this pipeline supports. See `CHANGELOG.md` §3 for the full root-cause writeup.

## Editing rules

- Keep `SetupComplete.cmd` **idempotent** — Setup can re-run it on repair scenarios
- Always log to `%WINDIR%\Setup\Scripts\SetupComplete.log`
- Do NOT block on user interaction (no `pause`, no `runas`, no GUI prompts)
- Do NOT take longer than ~10 minutes; Setup times out at 1 hour but UX suffers
- Any change requires RFC + IT Architecture approval (this is privileged SYSTEM code running pre-logon)
