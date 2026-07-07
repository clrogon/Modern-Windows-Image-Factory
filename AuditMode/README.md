# AuditMode\ — Audit-Mode Scripts

**Parent project:** Windows 11 Image Builder v2.3
**Phase:** Post-install, pre-Sysprep (runs on the reference VM, NOT the build server)

---

## What this folder is

Scripts that run on the **reference VM** during Windows audit mode, AFTER
the custom ISO has been installed and BEFORE Sysprep + capture.

This fills the gap between the ISO build (Scripts\ 01-11, build server)
and the Sysprep/capture step.

---

## Contents

| File | Purpose | Run order |
|---|---|---|
| `Apply-SecurityBaseline.ps1` | Apply Microsoft Security Baseline + CIS-aligned hardening (G1) - see its own header for exactly what's covered (v2.6) | First |
| `Apply-PostInstallCustomization.ps1` | Re-apply G7 tasks if SetupComplete.cmd failed silently | Only if needed |
| `README.md` | This file | n/a |

---

## Delivery to the reference VM

Script `10-Build-OemLayer.ps1` packs this folder into:

```
sources\$OEM$\$1\AuditMode\
```

Windows Setup copies `$OEM$\$1\` contents to `C:\` during install,
so these files land at:

```
C:\AuditMode\
C:\AuditMode\Apply-SecurityBaseline.ps1
C:\AuditMode\Apply-PostInstallCustomization.ps1
C:\AuditMode\README.md
C:\AuditMode\LGPO\LGPO.exe
C:\AuditMode\LGPO\Machine-*.txt           (curated ORG overrides)
C:\AuditMode\LGPO\User-*.txt              (curated ORG overrides)
C:\AuditMode\SCT\<baseline folder>\       (Microsoft SCT extract)
C:\AuditMode\Logs\                        (created at runtime)
```

> **`LGPO\` and `SCT\` are top-level repo folders** (siblings of `AuditMode\`,
> not nested inside it — see the root README's folder structure). Script `10`
> (`10-Build-OemLayer.ps1` Step 7b, v2.6) robocopies them into
> `$OEM$\$1\AuditMode\LGPO` and `\SCT` alongside the `AuditMode\` folder
> itself, so they land at the paths above automatically — no manual copy step
> on the reference VM, as long as you've populated the top-level `LGPO\` and
> `SCT\` folders (see their own READMEs) before running script 10. If either
> is empty at build time, script 10 logs a `WARN` and skips it; `LGPO.exe`
> just won't be present on the reference VM in that case.

---

## Required content before building the ISO

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
- Hardening report shows all PASS
- Visual verification of branding (lock screen, wallpaper, OEM Info)

---

## Script comparison

| Aspect | Apply-SecurityBaseline | Apply-PostInstallCustomization |
|---|---|---|
| Purpose | G1 compliance (SCT + CIS + VBS/HVCI/CG) | G7 re-apply (branding / OEM Info / CMTrace / region) |
| Required for production builds | Yes | No (diagnostic only) |
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
