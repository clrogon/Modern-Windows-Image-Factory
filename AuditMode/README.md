# AuditMode\ — Audit-Mode Scripts

**Parent project:** Windows 11 Image Builder v2.3
**Phase:** Post-install, pre-Sysprep (runs on the reference VM, NOT the build server)

---

## What this folder is

Scripts that run on the **reference VM** during Windows audit mode, AFTER
the custom ISO has been installed and BEFORE Sysprep + capture.

This fills the gap between the ISO build (Scripts\ 01-11, build server)
and the Sysprep/capture step.

> **Status note:** `Apply-SecurityBaseline.ps1`, described throughout this
> document, is **not yet shipped** in this repo — see `ROADMAP.md` (Security,
> v2.6) and `ARCHITECTURE.md` §6 (Known gaps). The steps below describe the
> target workflow once it lands. Until then, only `Apply-PostInstallCustomization.ps1`
> actually exists in this folder, and the rest of the audit-mode flow (choosing
> THIN/THICK, Sysprep, capture) works fine without it.

---

## Contents

| File | Purpose | Run order |
|---|---|---|
| `Apply-SecurityBaseline.ps1` | Apply Microsoft Security Baseline + CIS L1 hardening (G1) — **not yet shipped, see status note above** | First |
| `Apply-PostInstallCustomization.ps1` | Re-apply G7 tasks if SetupComplete.cmd failed silently | Only if needed |
| `README.md` | This file | n/a |

---

## Delivery to the reference VM

Script `10-Build-OemLayer.ps1` packs this folder (only this folder — see note
below) into:

```
sources\$OEM$\$1\AuditMode\
```

Windows Setup copies `$OEM$\$1\` contents to `C:\` during install,
so these files land at:

```
C:\AuditMode\
C:\AuditMode\Apply-PostInstallCustomization.ps1
C:\AuditMode\README.md
C:\AuditMode\Logs\                        (created at runtime)
```

> **`LGPO\` and `SCT\` are top-level repo folders (siblings of `AuditMode\`,
> not nested inside it — see the root README's folder structure), and script
> `10` does not currently stage either of them into the `$OEM$` tree at all.**
> The paths below (`AuditMode\LGPO\...`, `AuditMode\SCT\...`) describe the
> target layout once `Apply-SecurityBaseline.ps1` ships and something stages
> them under `C:\AuditMode\` on the reference VM — today, populate the
> top-level `LGPO\README.md` and `SCT\README.md` folders as documented there,
> and treat their delivery into the built ISO as part of the same
> not-yet-shipped gap (`ROADMAP.md`, Security, v2.6).

---

## Required content before building the ISO

*(Roadmap — see the status note above. Documents the target layout for once
`Apply-SecurityBaseline.ps1` ships and stages these onto the reference VM.)*

| Item | Where | Source |
|---|---|---|
| `LGPO.exe` | `AuditMode\LGPO\` | Microsoft Security Compliance Toolkit download |
| SCT baseline extract | `AuditMode\SCT\` | Microsoft Security Baseline for Win11 25H2 |
| Curated policy files | `AuditMode\LGPO\Machine-*.txt`, `User-*.txt` | Generated from GPO backups using `LGPO.exe /parse` |

The SCT download from Microsoft extracts to a folder named like
`Windows 11 v25H2 Security Baseline`. Place that entire folder (unmodified)
inside `AuditMode\SCT\`.

---

## Usage on the reference VM

*(Steps 2, 3, and 5 depend on `Apply-SecurityBaseline.ps1`, which is roadmap —
see the status note at the top of this document. Steps 1, 6, and 7 work today.)*

### Step 1 - Boot into audit mode
After installing from the custom ISO, at the OOBE screen press
**Ctrl+Shift+F3** to enter audit mode.

### Step 2 - Dry run hardening
```powershell
cd C:\AuditMode
.\Apply-SecurityBaseline.ps1
```
Review `C:\AuditMode\Logs\AuditMode-Baseline-DRYRUN-*.log`.

### Step 3 - Apply hardening
```powershell
.\Apply-SecurityBaseline.ps1 -Apply $true
```

### Step 4 - Reboot
VBS, HVCI, and Credential Guard require a reboot to activate.
```powershell
Restart-Computer
```
The machine returns to audit mode after reboot.

### Step 5 - Verify hardening
```powershell
.\Apply-SecurityBaseline.ps1 -VerifyOnly
```
Review `C:\AuditMode\Logs\HardeningReport-*.txt`. ALL checks must show `[PASS]`.

### Step 6 (OPTIONAL) - Re-apply post-install customization
Only run this if SetupComplete.cmd failed silently and you can see:
- No ORG wallpaper on the Welcome screen
- No ORG lock screen
- Settings > About shows no OEM Information
- .log files don't open in CMTrace

```powershell
.\Apply-PostInstallCustomization.ps1                 # dry run
.\Apply-PostInstallCustomization.ps1 -Apply $true    # apply
```

In normal builds this step is NOT required — `SetupComplete.cmd` handles
G7 tasks during install. This script exists only for diagnostic / repair
scenarios where you don't want to rebuild the ISO just to test a fix.

### Step 7 - Proceed to Sysprep
Only after:
- Hardening report shows all PASS (once `Apply-SecurityBaseline.ps1` ships — see status note; today, skip this gate)
- Visual verification of branding (lock screen, wallpaper, OEM Info)

---

## Script comparison

| Aspect | Apply-SecurityBaseline (roadmap, not yet shipped) | Apply-PostInstallCustomization |
|---|---|---|
| Purpose | G1 compliance (SCT + CIS + VBS/HVCI/CG) | G7 re-apply (branding / OEM Info / CMTrace / region) |
| Required for production builds | Yes, once shipped | No (diagnostic only) |
| Modifies machine state | Yes (registry, GPO, LSA) | Yes (registry, Default user hive) |
| Reboot required after | Yes (VBS/HVCI/CG activation) | No |
| Produces compliance evidence | Yes (`HardeningReport-*.txt`) | No (re-applies SetupComplete tasks) |

---

## Cleanup after Sysprep

The `C:\AuditMode\` folder persists in the captured image. Options:

1. **Keep it** — useful for re-verification on deployed machines
2. **Delete before Sysprep** — reduces image size, removes tools from endpoints
3. **Add to Sysprep unattend** — `RunSynchronous` command in `<settings pass="generalize">` to delete it

Recommendation: keep `Logs\HardeningReport-*.txt` for audit evidence,
delete the rest before Sysprep:
```powershell
# Before sysprep:
Move-Item C:\AuditMode\Logs\HardeningReport-*.txt C:\Windows\Setup\Logs\
Remove-Item C:\AuditMode -Recurse -Force
```
