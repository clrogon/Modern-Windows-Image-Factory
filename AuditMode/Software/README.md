# AuditMode\Software\ - Thick-image software layer

**Parent project:** Windows 11 Image Builder
**Phase:** Reference VM, audit mode, AFTER Apply-SecurityBaseline.ps1, BEFORE Sysprep + capture.

---

## Thin vs Thick

| | THIN | THICK |
|---|---|---|
| OS + drivers + branding + hardening | Yes | Yes |
| Common software baked in | No | Yes (M365, Adobe Acrobat, + whatever you add) |
| Apps delivered | At deployment (MDT / Intune / M365 C2R) | In the image |
| Image size | Small | Larger |
| Use when | Apps vary by role; fast re-image | Standard fleet build, fewer post-deploy steps |

**One base, divergence at audit mode.** Both variants run the same 01-11 build-server pipeline and produce the same base ISO. The only difference is whether you run `Install-ImageSoftware.ps1 -ImageProfile Thick` in audit mode before Sysprep. There is no forked pipeline.

---

## Everything rides the ISO (self-contained, fully disconnected)

All installer binaries are staged into `<ProjectRoot>\AuditMode\Software\` on the build
server. Script 10 copies the entire `AuditMode\` tree into `$OEM$\$1\AuditMode`, and
11 packs it into the ISO. When the ISO installs on the reference VM, everything
lands at `C:\AuditMode\Software\` automatically - no USB hand-copy, no network share,
no separate staging step. The ISO is the single, self-contained build medium.

**Build-server layout (stage binaries here before running 10):**
```
<ProjectRoot>\AuditMode\Software\
    Install-ImageSoftware.ps1  (version-controlled - ships in ZIP)
    README.md                       (version-controlled)
    ODT\
        setup.exe                   (Office Deployment Tool - download from Microsoft)
        ODT_SemiAnnual.xml     (version-controlled config)
        Download-OfficeSource.ps1   (version-controlled helper)
        Office\Data\<build>\        (created by Download-OfficeSource.ps1 -Apply)
    AdobeAcrobat\
        build\          setup.exe + Acrobat.msi (~2.7 GB, from Adobe Admin Console)
    YourApp\
        YourApp.msi     (drop any additional MSI/EXE here, see Install-ImageSoftware.ps1 template)
```
The ZIP (version-controlled) ships the scripts, config, and README. The large binaries
(Office source ~4 GB, MSIs) are staged into the same tree after extraction but are NOT
checked into version control (large + licensed).

**Reference VM path:** `C:\AuditMode\Software\` (via $OEM$ - automatic).

**Pre-Sysprep cleanup (CRITICAL):** after the thick install (or on thin builds where
the binaries rode along unused), delete the installer tree before capture so it does
not ship ~4+ GB of dead weight to every deployed machine:
```powershell
Remove-Item -Path C:\AuditMode -Recurse -Force
```

> OneDrive / Teams - enterprise versions ARE in THICK, via ODT:
> The CONSUMER/inbox OneDrive and Teams clients are removed offline (script 06;
> Lists/ApprovedRemoval-Apps.txt) because those bundled clients caused repeated
> deployment failures (personal-account prompts, stale tenant cache, double
> icons) that forced the support team to manually uninstall/reinstall. The
> ENTERPRISE OneDrive for Business and Teams (work) clients are different
> products - they now install as part of the M365 Apps ODT config
> (`AuditMode/Software/ODT/ODT_SemiAnnual.xml`, no longer excluded), signed in
> to the ORG tenant like the rest of Office.

> ODT note: no `SourcePath` in the config (removed for portability). setup.exe
> resolves `Office\Data` relative to its working directory. Both the download helper
> and the installer set `-WorkingDirectory` to the ODT folder, so it works on the
> build server (`<ProjectRoot>\...`) and the reference VM (`C:\AuditMode\...`) without path conflicts.
> `AllowCdnFallback=FALSE` means the source MUST be present locally.

---

## Office source - pre-download FIRST (deterministic, offline-safe)

Download the M365 source ONCE on a machine with internet (build server / staging
workstation - never the audit VM), then reuse it. Downloading on every build would
pull a different channel build each day; pre-downloading pins it.

```powershell
# On the build server (needs internet for this one step only).
cd <ProjectRoot>\AuditMode\Software\ODT
.\Download-OfficeSource.ps1                 # dry run (validates setup.exe + config)
.\Download-OfficeSource.ps1 -Apply $true    # downloads to ODT\Office\Data\<build>
```

The helper records the staged build and a review-by date in
`STAGED-OFFICE-VERSION.txt` in the ODT folder. Then run `10-Build-OemLayer.ps1` and
`11-Build-Iso.ps1` to rebuild the ISO (the source rides to the VM automatically). In audit mode the installer runs `setup.exe /configure`
(offline, from the local source). Do NOT inject Office into install.wim - it is
Click-to-Run and must install on a live OS.

## Adobe Acrobat - getting the installer + transform

The current consumer/unified Acrobat installer requires interactive sign-in, which
will NOT work for silent imaging (no user is signed in during audit mode). Use the
enterprise path:

1. **Create a package** in the **Adobe Admin Console** (Packages > Create a Package >
   Acrobat Pro DC, 64-bit). Configure silent install settings, EULA acceptance, and
   update behaviour in the Admin Console before building the package - the
   customisation is baked in (no separate Customization Wizard / `.mst` needed).
2. **Download the package** (~2.7 GB). It contains a `build\` subfolder with
   `setup.exe` + `Acrobat.msi` and supporting files.
3. **Stage the package as-is** at `<ProjectRoot>\AuditMode\Software\AdobeAcrobat\` (keep
   the `build\` subfolder structure). The installer runs `setup.exe --silent`.
4. Named-user activation happens at first user sign-in post-deploy - do NOT
   activate in the image.

## Review cadence (every ~6 months)

The THICK software set should be refreshed periodically (you flagged this for review
in a few months):
- Re-run `Download-OfficeSource.ps1 -Apply $true` to refresh the SAEC source (feature
  updates land ~January and ~July); check `STAGED-OFFICE-VERSION.txt`.
- Re-download the current Adobe Acrobat MSI from the Admin Console and rebuild the .mst
  if the Wizard version changed.
- Re-verify any additional packages you've added to `$AppDefinitions` against current
  approved versions on the same cadence.

---

## Usage (reference VM, audit mode)

```powershell
cd C:\AuditMode\Software
.\Install-ImageSoftware.ps1 -ImageProfile Thick -DryRun   # validate paths
.\Install-ImageSoftware.ps1 -ImageProfile Thick           # install
# THIN build: skip this folder entirely (or run -ImageProfile Thin = no-op)
```

Then reboot if prompted, verify, Sysprep + capture.

---

## Confirmed decisions

1. **Consumer OneDrive/Teams are removed offline; enterprise OneDrive for Business + Teams (work) ship in THICK via ODT.** These are different products - the consumer/inbox clients caused the repeated deployment failures (personal-account prompts, stale tenant cache, double icons), not the enterprise ones. Removed offline (script 06, Lists), installed via M365 ODT (no longer excluded). Keep the image-vs-GPO split table (Appendix F) consistent with this.
2. **Only M365 Apps and Adobe Acrobat ship as examples in THICK.** They're the two installer patterns (ODT and silent EXE) you'll need for almost anything else you add - copy the template entry in `Install-ImageSoftware.ps1` for additional packages.

---

## Review notes on the supplied files (v1.0 -> v1.1)

`Install-ImageSoftware.ps1`:
- Removed all non-ASCII (box-drawing, em-dashes, emoji) - violated the project ASCII-only rule and renders as garbage in the PS 5.1 console.
- Renamed `-Profile` to `-ImageProfile` - `$Profile` shadows the PowerShell automatic variable `$PROFILE`.
- Profile logic re-aligned to the stated goal: common apps moved from `Both` to `Thick`; THIN now installs nothing. (As supplied, THIN already contained all common apps and differed from THICK only by one departmental app - the opposite of the requirement.)
- Colours aligned to the 01-11 suite (ERROR/WARN/OK + new NEXT=Cyan; INFO uncoloured).
- OneDrive/Teams removed from the install set entirely (ORG decision: not in the image); ODT exclusions retained so M365 cannot re-add the per-user clients.
- Added `-NoReboot`; target note corrected to 25H2.

`ODT_SemiAnnual.xml`: functionally sound. ASCII-cleaned (comment em-dashes / accented name) and added an XML declaration.
