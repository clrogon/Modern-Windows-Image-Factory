# Scripts\

Strict sequential two-digit prefixes (`01-`, `02-`, `03-`...), no letter suffixes.
Sort order = run order, full stop. Verb-first PowerShell-style names
(`Remove-`, `Enable-`, `Import-`, `Build-`) describe what each script actually
does, not where it sits relative to some other script.

Diagnostics are pulled out of the numbered sequence entirely, into
`Diagnostics\`, because they're read-only and safe to run any time — mixing
them into the main sequence (as `03a-`, `03b-` in an earlier version of this
pipeline) implied an ordering dependency that didn't exist and obscured which
scripts actually mutate state.

## Run as Administrator

Every script in this suite requires an elevated PowerShell session -
`Mount-WindowsImage`, `Get-WindowsImage -Mounted`, DISM operations, and
folder creation under drive roots all need it. Scripts enforce this with
`#Requires -RunAsAdministrator` at the top: run one from a non-elevated
prompt and PowerShell refuses to start it with a clear error, instead of
failing partway through with a confusing access-denied exception.

## Configuration: `BuildConfig.psd1`

ISO path, mount point, WIM index, ADK location, and build-server root are
defined once in `BuildConfig.psd1`, not copy-pasted as literals into every
script. Every script exposes the same values as parameters that override the
config default for a single run without editing the file:

```powershell
.\04-Remove-ProvisionedApps.ps1 -MountPath 'D:\Mount' -Apply
```

Edit `BuildConfig.psd1` when your ISO filename, drive letters, or WIM index
change permanently. This also means every script agrees on the mount path by
construction — they all read the same file, instead of each hardcoding
`E:\WimMount` independently and risking one getting edited without the
others.

| # | File | Purpose | Mutates state | Run frequency |
|---|---|---|---|---|
| 01 | `01-Unblock-Scripts.ps1` | Strip MOTW, check exec policy, prep runtime folders | No | Once per ZIP extraction |
| 02 | `02-Extract-Iso.ps1` | Mount retail/MLF ISO, robocopy contents, clear read-only | Yes | Per new ISO release |
| 03 | `03-Initialize-BuildEnvironment.ps1` | Verify folder layout, tool availability, ADK | No | First-time + after changes |
| 04 | `04-Remove-ProvisionedApps.ps1` | Mount WIM, remove provisioned AppX + capabilities (leaves mounted) | Yes | Per build |
| 05 | `05-Remove-SystemApps.ps1` | Remove SystemApps (Quick Assist, web search, legacy assistant) that AppX removal can't touch | Yes | Per build (after 04) |
| 06 | `06-Remove-OneDrive.ps1` | Remove OneDriveSetup.exe + apply reinstall-suppression keys in offline hive | Yes | Per build |
| 07 | `07-Enable-DotNet35.ps1` | Enable .NET Framework 3.5 offline via DISM | Yes | Per build |
| 08 | `08-Import-DefaultAppAssociations.ps1` | Import default file-type associations offline via DISM | Yes | Per build |
| 09 | `09-Dismount-Image.ps1` | Dismount WIM with `-Save` (commits 04-08) | Yes | Per build |
| 10 | `10-Build-OemLayer.ps1` | Build the `sources\$OEM$\` tree: drivers, branding, SetupComplete | Yes | Per build |
| 11 | `11-Build-Iso.ps1` | Repackage bootable UEFI ISO + SHA256 manifest | Yes | Per build |
| — | `Diagnostics\Diagnose-AppxAndCapabilities.ps1` | What's in the mounted image vs. what your removal list matches | No | When investigating removal issues |
| — | `Diagnostics\Diagnose-Removal.ps1` | General diagnostic for removal investigation | No | When something's not right |

## Run order (production)

```powershell
Set-Location <ProjectRoot>\Scripts

# First-time setup
.\01-Unblock-Scripts.ps1
.\03-Initialize-BuildEnvironment.ps1

# Per-build (each dry-runs by default, pass -Apply to actually change anything)
.\02-Extract-Iso.ps1 -Apply
.\04-Remove-ProvisionedApps.ps1 -Apply           # Mounts WIM, removes provisioned AppX
.\05-Remove-SystemApps.ps1 -Apply                # Removes SystemApps (Quick Assist etc.)
.\06-Remove-OneDrive.ps1 -Apply                  # OneDrive + reinstall-suppression keys
.\07-Enable-DotNet35.ps1 -Apply                  # Offline DISM feature enable
.\08-Import-DefaultAppAssociations.ps1 -Apply    # Offline DISM associations import
.\09-Dismount-Image.ps1 -Apply                   # Commits all changes
.\10-Build-OemLayer.ps1 -Apply
.\11-Build-Iso.ps1 -Apply
```

## Why three separate offline-removal scripts (04, 05, 06)?

Three different removal mechanisms because Windows 11 ships three different
kinds of "bloatware":

| Type | Example | Mechanism | Script |
|---|---|---|---|
| Provisioned AppX | Bing News, Solitaire, Xbox apps | `Remove-AppxProvisionedPackage` | 04 |
| System apps (folder under SystemApps) | Quick Assist, web search, legacy assistant | `takeown` + `Remove-Item` | 05 |
| Per-user MSI bootstrap + reinstall fetchers | OneDriveSetup, ContentDeliveryManager re-fetch | File removal + offline registry edit | 06 |

A single script could do all three, but separation keeps each clear and
independently debuggable. All three (plus 07, 08) run while the WIM is
mounted by script 04; script 09 commits the combined result.

## Recovery commands (manual)

Replace `E:\WimMount` below with your actual `MountPath` from
`BuildConfig.psd1` if you've overridden the default.

```powershell
# Check what's mounted
Get-WindowsImage -Mounted

# Save changes and dismount
Dismount-WindowsImage -Path E:\WimMount -Save

# Discard changes and dismount (lose all servicing)
Dismount-WindowsImage -Path E:\WimMount -Discard

# Force-clear a stuck mount
Clear-WindowsCorruptMountPoint

# Strip MOTW from a single file
Unblock-File -Path '.\04-Remove-ProvisionedApps.ps1'

# Change execution policy for current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```
