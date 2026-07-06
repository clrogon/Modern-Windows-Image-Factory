# Architecture

This document describes how Modern Windows Image Factory is put together: the two build
phases, the pipeline that runs on each, and how files move from the repo into the final
deployed machine. For "what to run and in what order," see `Scripts/README.md` and
`AuditMode/README.md` — this document is the map of *why* it's structured this way.

The diagrams below are also kept as standalone Mermaid source files in
[`docs/diagrams/`](docs/diagrams) so they can be rendered outside GitHub (mermaid CLI,
mermaid.live, Confluence, etc.) without copy-pasting out of this file.

## 1. Two-phase system

The build is split across two machines that never need to be the same box:

- **Build server** (`Scripts/01-11`) — offline DISM servicing of `install.wim` plus an
  ISO repackage. No VM required, nothing here boots Windows.
- **Reference VM** (`AuditMode/`) — boots the custom ISO into audit mode, applies the
  security baseline (see [gaps](#4-known-gaps) below), optionally layers software, then
  Sysprep + capture.

```mermaid
flowchart TB
    subgraph Inputs["Operator-provided inputs (not shipped in the repo)"]
        ISO["Win11 Enterprise/Pro ISO"]
        ADK["Windows ADK (oscdimg.exe)"]
        Lists["Lists/ removal lists"]
        Branding["Branding/ wallpaper + lock screen"]
        Drivers["Drivers-SCCM/ driver trees"]
        Baseline["SCT/ + LGPO/ + GPO-Backup/"]
        Software["AuditMode/Software/ installer binaries"]
    end

    subgraph BuildServer["Phase 1 - Build Server (Scripts/ 01-11)"]
        Pipeline["Offline WIM servicing\n+ OEM layer\n+ ISO repackage"]
    end

    subgraph RefVM["Phase 2 - Reference VM (AuditMode/)"]
        Audit["Audit mode:\nhardening baseline (roadmap)\n+ software layer (THIN/THICK)\n+ Sysprep"]
    end

    Inputs --> BuildServer
    BuildServer -->|"Custom bootable ISO"| RefVM
    RefVM -->|"Sysprep /generalize + capture"| Image["Captured reference WIM\n(THIN or THICK)"]
    Image --> Deploy["MDT / SCCM / Intune / Autopilot / USB install"]
```

Two variants come out of one base image (see `AuditMode/Software/README.md`):

| Variant | Contents |
|---|---|
| **THIN** | OS + drivers + branding + hardening. No apps — layered at deployment time. |
| **THICK** | THIN + M365 Apps (ODT) + Adobe Acrobat, as worked examples of the two installer patterns used for anything else you add. |

## 2. Build-server pipeline (`Scripts/01-11`)

Eleven scripts, strict two-digit run order, verb-first names. `install.wim` is mounted
by `04` and stays mounted through `08` so those five scripts can service the same offline
image; `09` is the single commit gate that dismounts with `-Save`.

```mermaid
flowchart TD
    Start(["Operator on build server"]) --> S01["01 Unblock-Scripts\nstrip MOTW, check exec policy, prep folders\n(no mutation)"]
    S01 --> S02["02 Extract-Iso\nmount ISO, robocopy, clear read-only\n(mutates E:\\ISO\\...)"]
    S02 --> S03["03 Initialize-BuildEnvironment\nverify layout, ADK, tools\n(no mutation)"]
    S03 --> S04["04 Remove-ProvisionedApps\nMOUNT install.wim, remove AppX + capabilities"]
    S04 --> S05["05 Remove-SystemApps\nremove SystemApps folders\n(Quick Assist, Search, Cortana)"]
    S05 --> S06["06 Remove-OneDrive\nremove OneDriveSetup.exe\n+ reinstall-suppression keys"]
    S06 --> S07["07 Enable-DotNet35\nenable NetFx3 offline via DISM"]
    S07 --> S08["08 Import-DefaultAppAssociations\noffline DISM default associations import"]
    S08 --> S09["09 Dismount-Image\nDISMOUNT install.wim -Save\n(commits 04-08)"]
    S09 --> S10["10 Build-OemLayer\nbuild sources\\$OEM$\\ tree:\ndrivers, branding, SetupComplete, AuditMode"]
    S10 --> S11["11 Build-Iso\nstage Autounattend.xml,\noscdimg bootable ISO, SHA256 manifest"]
    S11 --> Out(["Win11_25H2_Custom.iso + manifest"])

    subgraph MOUNTED["install.wim mounted at E:\\WimMount"]
        S04
        S05
        S06
        S07
        S08
    end

    Diag1["Diagnostics\\Diagnose-AppxAndCapabilities.ps1\n(read-only)"] -.->|"run anytime while mounted"| MOUNTED
    Diag2["Diagnostics\\Diagnose-Removal.ps1\n(read-only)"] -.->|"run anytime while mounted"| MOUNTED

    style MOUNTED fill:#00000000,stroke-dasharray: 5 5
```

Every mutating script (`02`, `04-11`) takes a `[switch]$Apply` parameter and dry-runs by
default — bare invocation only logs what it *would* do; pass `-Apply` to actually change
anything. `Diagnostics\` scripts are pulled out of the numbered sequence entirely because
they're read-only and safe to run at any point once the WIM is mounted.

## 3. `$OEM$` delivery mapping

Script `10` builds the `sources\$OEM$\` tree Windows Setup processes automatically during
install (no unattend.xml entry required to trigger it); script `11` bakes that tree, plus
`Autounattend.xml`, into the final ISO with `oscdimg`.

```mermaid
graph LR
    subgraph ISO["Build media: sources\\$OEM$\\ tree (built by script 10)"]
        A["$$\\Setup\\Scripts\\SetupComplete.cmd"]
        B["$$\\Web\\Wallpaper\\CompanyBrand\\Wallpaper.jpg"]
        C["$$\\Web\\Wallpaper\\CompanyBrand\\LockScreen.jpg"]
        D["$1\\Drivers\\ (full Drivers-SCCM tree)"]
        E["$1\\AuditMode\\ (hardening + software scripts)"]
        F["$$\\System32\\CMTrace.exe"]
        G["Autounattend.xml (ISO root, staged by script 11)"]
    end

    subgraph TARGET["Target machine after Windows Setup"]
        A2["C:\\Windows\\Setup\\Scripts\\SetupComplete.cmd"]
        B2["C:\\Windows\\Web\\Wallpaper\\CompanyBrand\\Wallpaper.jpg"]
        C2["C:\\Windows\\Web\\Wallpaper\\CompanyBrand\\LockScreen.jpg"]
        D2["C:\\Drivers\\"]
        E2["C:\\AuditMode\\"]
        F2["C:\\Windows\\System32\\CMTrace.exe"]
        G2["Answers Setup prompts,\nenters audit mode automatically"]
    end

    A -->|"$$ = %WINDIR%"| A2
    B -->|"$$ = %WINDIR%"| B2
    C -->|"$$ = %WINDIR%"| C2
    D -->|"$1 = system drive"| D2
    E -->|"$1 = system drive"| E2
    F -->|"$$ = %WINDIR%"| F2
    G --> G2

    A2 -->|"reads at first boot, as SYSTEM"| B2
    A2 -->|"reads at first boot, as SYSTEM"| C2
    A2 -->|"DevicePath + pnputil scan"| D2
    G2 -->|"FirstLogonCommands: sysprep /audit /reboot"| E2
```

`SetupComplete.cmd` (`OEM-Template/SetupComplete.cmd`) is the consumer half of this
contract — it runs as SYSTEM, before OOBE, and reads the exact paths script `10` writes
to. See `CHANGELOG.md` §2 for what happens when the two sides of that contract disagree
(a real incident this pipeline hit and fixed).

## 4. Reference VM / audit-mode phase

```mermaid
flowchart TD
    Boot(["Ctrl+Shift+F3 at OOBE\n-> enters audit mode"]) --> SecBaseline["Apply-SecurityBaseline.ps1\n(NOT YET SHIPPED - see ROADMAP v2.6)"]
    SecBaseline -.->|"roadmap only"| Reboot1["Reboot\n(VBS / HVCI / Credential Guard activation)"]
    Reboot1 -.-> Verify["Apply-SecurityBaseline.ps1 -VerifyOnly\n(roadmap only)"]
    Verify -.-> Fix{"Branding / OEM info\nshowing correctly?"}
    SecBaseline --> Fix
    Fix -->|"No"| PostInstall["Apply-PostInstallCustomization.ps1\n(diagnostic re-apply, optional)"]
    Fix -->|"Yes"| Profile
    PostInstall --> Profile["Choose image profile"]
    Profile -->|"THIN"| SysprepThin["No software baked in"]
    Profile -->|"THICK"| SoftwareInstall["Install-ImageSoftware.ps1 -ImageProfile Thick\n(M365 via ODT, Adobe Acrobat)"]
    SoftwareInstall --> Cleanup
    SysprepThin --> Cleanup["Cleanup (manual step today):\ndelete C:\\AuditMode\n(C:\\Drivers is auto-removed by\nSetupComplete.cmd Task 6)"]
    Cleanup --> Sysprep["Sysprep /generalize /oobe /shutdown"]
    Sysprep --> Capture["Capture WIM\n(DISM / MDT / SCCM)"]
    Capture --> Deploy["Deploy via MDT / SCCM / Intune / Autopilot"]

    style SecBaseline fill:#00000000,stroke-dasharray: 5 5
    style Reboot1 fill:#00000000,stroke-dasharray: 5 5
    style Verify fill:#00000000,stroke-dasharray: 5 5
```

The dashed nodes are the documented-but-not-yet-shipped hardening step (`ROADMAP.md`,
v2.6 Security section) — see [Known gaps](#4-known-gaps).

## 5. Configuration inputs

Everything the pipeline consumes but doesn't ship pre-populated:

| Folder | Feeds | Status |
|---|---|---|
| `Lists/` | Script `04` (AppX + capability removal) | Shipped, curated |
| `Branding/` | Script `10` (wallpaper/lock screen) | Empty — bring your own |
| `Defaults/` | Script `08` (default app associations, WiFi profile) | Empty — sourced from your domain |
| `Drivers-SCCM/` | Script `10` (driver staging) | Not tracked — populate before building |
| `GPO-Backup/`, `LGPO/`, `SCT/` | `AuditMode/` hardening baseline (roadmap) | Empty — populate from Microsoft SCT + your domain GPOs |
| `OEM-Template/` | Scripts `10` and `11` (`SetupComplete.cmd`, `Autounattend.xml`) | Shipped with placeholders — replace before production |
| `unattend/` | Sysprep / MDT answer files | Templates needed — build with Windows SIM |
| `AuditMode/Software/` | `Install-ImageSoftware.ps1` (THICK builds) | Scripts/config shipped; binaries staged locally, not tracked |

## 6. Known gaps

- **`Apply-SecurityBaseline.ps1` is not implemented yet.** It's referenced throughout
  `AuditMode/README.md` and the `Release v2.5.0` notes as the CIS/VBS/HVCI/Credential
  Guard hardening step, but the file doesn't exist in this repo — see `ROADMAP.md`
  (Security, v2.6). Everything downstream of it in the audit-mode flow above still works
  without it; you just won't have the automated baseline until it ships.
- **No CI.** `ROADMAP.md` lists PSScriptAnalyzer and a GitHub Actions validation
  pipeline as v2.6 targets — today nothing automatically checks the PowerShell in this
  repo on push.
- **`C:\AuditMode` cleanup is manual**, not scripted (see
  `AuditMode/Software/README.md`). Forgetting it ships installer binaries and hardening
  scripts to every deployed endpoint. (`C:\Drivers` is no longer in this category —
  `SetupComplete.cmd` Task 6, v2.5+, removes it automatically after the PnP scan.)

## 7. Where the diagrams live

The four diagrams above are duplicated as standalone `.mmd` files in
[`docs/diagrams/`](docs/diagrams) so they can be fed into the Mermaid CLI, mermaid.live,
or a docs pipeline without extracting them from this file:

| File | Diagram |
|---|---|
| `docs/diagrams/system-overview.mmd` | §1 Two-phase system |
| `docs/diagrams/build-pipeline.mmd` | §2 Build-server pipeline |
| `docs/diagrams/oem-delivery-mapping.mmd` | §3 `$OEM$` delivery mapping |
| `docs/diagrams/audit-mode-flow.mmd` | §4 Reference VM / audit-mode phase |

If you change one, change both copies — they're plain duplicated content, not generated
from a single source.
