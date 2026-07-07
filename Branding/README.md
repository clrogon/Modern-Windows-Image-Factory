# Branding\

Static branding assets staged into the `$OEM$` tree by script `10`
(`10-Build-OemLayer.ps1`, Phase 1 — build server) and applied to the desktop
and lock screen at first boot by `SetupComplete.cmd` (see `ARCHITECTURE.md` §3).

| File | Destination in image | Source GPO |
|---|---|---|
| `LockScreen.jpg` | `C:\Windows\Web\Wallpaper\CompanyBrand\` | GPP File from \\netlogon (lock screen) |
| `Wallpaper.jpg` | `C:\Windows\Web\Wallpaper\CompanyBrand\` | GPP File from \\netlogon (default wallpaper) |
| `Wallpaper_Alt.jpg` | `C:\Windows\Web\Wallpaper\CompanyBrand\` | Brand asset library (alternate wallpaper) |

**Status:** EMPTY — copy current production assets from `\\corp.contoso.local\netlogon\` and the brand asset library.

Files in this folder are PUBLISHED via the image, so version-control them and review on every revision.
