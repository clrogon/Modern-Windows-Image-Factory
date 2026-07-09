## v2.6.1 - OEM-layer crash fix + release packaging scope

Patch release on top of v2.6. One bug fix, one release-process change. No new
scripts, no behavioural change to the build pipeline itself.

### Fixed

- **`Scripts/10-Build-OemLayer.ps1`**: fixed a `Set-StrictMode` crash
  (`PropertyNotFoundException` on `.Count`) that hit Step 7b (LGPO/SCT
  staging) whenever one of those source folders contained exactly one
  file/folder. `Get-ChildItem -Recurse` unwraps a single-item result to a
  bare object with no `.Count` property, and `Set-StrictMode -Version Latest`
  throws on that instead of treating it as `$null`. Wrapped both that check
  and the equivalent one in Step 6 (`Drivers-SCCM` staging, same latent bug)
  in `@(...)` so the result is always a proper array regardless of item
  count.

### Changed

- **Release packaging** (`.github/workflows/release.yml`): release `.zip`
  assets now contain only the 13 top-level runtime folders documented in
  README.md's "Folder structure" (`AuditMode/`, `Branding/`, `Defaults/`,
  `Drivers-SCCM/`, `GPO-Backup/`, `LanguagePacks/`, `LGPO/`, `Lists/`,
  `OEM-Template/`, `SCT/`, `Scripts/`, `Software/`, `unattend/`), instead of a
  `git archive` of the entire tagged tree. GitHub's Clone/Download ZIP
  buttons already cover the full source (docs, CI config, tests); the
  release asset now matches what an operator actually copies onto the build
  server.
- Added `README.md` placeholders to `Drivers-SCCM/`, `LanguagePacks/`, and
  `Software/` — previously untracked "not shipped" folders with nothing in
  the repo tree at all — so they exist to be archived and explain what goes
  there, matching every other empty runtime folder (`Branding/`, `Defaults/`,
  `GPO-Backup/`, etc.).

---

## v2.6 - Security baseline, image engineering automation, CI/release pipeline

Delivers every item tracked under "Version 2.6" in `ROADMAP.md` (now moved there to
"Delivered" - see that file). Three areas:

### Security

- **`AuditMode/Apply-SecurityBaseline.ps1` ships.** This was the long-documented gap
  (`ARCHITECTURE.md` Known gaps, referenced throughout `AuditMode/README.md` since v2.4) -
  every hardening claim in prior release notes was explicitly roadmap-only until now. Three
  layers, each independently toggleable via `-SkipTasks`:
  - Microsoft Security Compliance Toolkit baseline application via `LGPO.exe`, if `LGPO/` and
    `SCT/` have been populated (they're still operator-populated and empty by default - this
    warns and continues rather than failing if they haven't been).
  - A curated CIS-Benchmark-aligned registry hardening subset: SMBv1 disabled, LLMNR disabled,
    AutoRun/AutoPlay disabled, UAC Admin Approval Mode, guest account disabled, anonymous
    SAM/share enumeration restricted, WDigest plaintext credential caching disabled, LSA
    Protection (RunAsPPL), PowerShell Script Block Logging, SmartScreen (Block mode), legacy
    TLS/SSL protocols disabled, and a minimum password length / lockout policy floor.
  - VBS + Hypervisor-Enforced Code Integrity (memory integrity), Credential Guard, the full
    current Microsoft Defender Attack Surface Reduction rule set (18 rules, GUIDs verified
    against Microsoft Learn at write time), and a BitLocker *policy* baseline (registry only -
    this script does not encrypt the reference VM itself; see its header for why).
  - `-VerifyOnly` produces `HardeningReport-*.txt` with a `[PASS]`/`[FAIL]` per check, matching
    the workflow `AuditMode/README.md` already documented.
- Registry values for VBS/HVCI/Credential Guard and Defender ASR rule GUIDs were checked
  against current Microsoft Learn documentation while writing this script, not reconstructed
  from memory - see the script's own `.NOTES` for what was verified against what.
- `10-Build-OemLayer.ps1` gained Step 7b: stages the top-level `LGPO/` and `SCT/` folders into
  `$OEM$\$1\AuditMode\LGPO` and `\SCT` (previously documented as a gap - script 10 only staged
  the `AuditMode/` folder itself), so `Apply-SecurityBaseline.ps1`'s default paths resolve on
  the reference VM without a manual copy step.

### Image Engineering

Four new, independently-optional scripts. Each is self-contained (mounts `install.wim`,
services it, dismounts `-Save` itself) rather than inserted into the existing `04`-`09` mount
window, specifically to avoid renumbering any of scripts `01`-`11` - see each script's `.NOTES`
and `CHANGELOG.md` v2.5.1 above for why stale/shifted script-number references are treated as a
real bug class in this repo. Run order: after `09-Dismount-Image.ps1`, before
`10-Build-OemLayer.ps1`.

- `Scripts/12-Inject-Drivers.ps1` - offline `Add-WindowsDriver` injection for drivers that need
  to be present in the image itself (typically storage/NIC) rather than staged for the
  post-boot PnP scan script `10`/`SetupComplete.cmd` already do.
- `Scripts/13-Add-LanguagePacks.ps1` - offline language pack CAB injection plus optional
  `Set-SKUIntlDefaults` to make it the image default.
- `Scripts/14-Add-FeaturesOnDemand.ps1` - offline `Add-WindowsCapability` from a local FOD
  source, driven by a new `Lists/ApprovedAdd-Capabilities.txt` (the addition-direction mirror
  of `Lists/ApprovedRemoval-Capabilities.txt`, same prefix-matching).
- `Scripts/15-Restore-MicrosoftStore.ps1` - optional recovery path for when Microsoft Store was
  stripped by a custom/inherited removal list against `Lists/README.md`'s own advice, or by a
  third-party debloat pass before this pipeline touched the image.

### Automation

- **CI**: `.github/workflows/validate.yml` runs PSScriptAnalyzer (via a new
  `PSScriptAnalyzerSettings.psd1`, with the repo's deliberate conventions - e.g. `Write-Host`
  for colored logging - excluded with rationale, not just silenced) plus XML well-formedness and
  a scoped placeholder-password leak check, on every push and PR. This repo had no CI before
  v2.6 (`ARCHITECTURE.md` Known gaps).
- **Release packaging**: `.github/workflows/release.yml`, triggered on `v*.*.*` tag push, gates
  on the same validation workflow, then packages a `git archive` of the tagged tree (tracked
  files only) with a SHA256 manifest, and publishes a GitHub Release with the matching
  `CHANGELOG.md` section as the release body.
- Fixed the four real (non-false-positive) findings PSScriptAnalyzer surfaced against the
  pre-v2.6 codebase before adding the CI gate: two unused variables (`05-Remove-SystemApps.ps1`,
  `07-Enable-DotNet35.ps1`/`10-Build-OemLayer.ps1` both had a dead `$Win11Version`), so the new
  gate starts green rather than immediately red on existing code.

---

## v2.5.1 - Reference consistency patch

Documentation/reference correctness only. **No functional, behavioural, or logic changes** — every
edit is inside a comment, log-banner string, or a cross-reference pointer. The build sequence,
parameters, and safety conventions (`-Apply` dry-run default) are untouched.

### Why this exists

The scripts were renamed to the sequential `01-` → `11-` convention several releases ago, but a
large amount of their *internal* metadata still pointed at the old `00`/`01`/`03a`/`03b`/`04b`/`04c`
scheme. Because old numbers now map to *different* files, several of these weren't merely stale —
they were actively wrong. Example: `04-Remove-ProvisionedApps.ps1` told the reader that "script 04
(OneDrive removal)" runs next, but script 04 is now that file itself; OneDrive removal is script 06.
Anyone following the pipeline step-by-step from the comments would be misdirected.

### Fixed

- Migrated every stale script-number reference to current numbering across all 11 build scripts and
  both diagnostics: file-header titles, `========== NN ... ==========` log banners, `Phase NN`
  summary strings, and backward "run script NN first" cross-references. Forward "Next: run NN-…"
  pointers were already correct and were left as-is.
- `Scripts/Diagnostics/Diagnose-AppxAndCapabilities.ps1`: header no longer labels itself `03a`
  (diagnostics are deliberately outside the numbered sequence — now labelled `Diagnostic:`).
- `OEM-Template/OEMDefaultAssociations.xml`: the inline DISM example referenced a non-existent file
  (`OEMDefaultAssociations-ORG.xml`) and the retired `04c` script number — corrected to the real
  filename and `script 08`.
- `OEM-Template/Autounattend.xml`: step references `03b`/`04b`/`04c` → `05`/`07`/`08`.
- OEM Support-provider placeholder unified: `Apply-PostInstallCustomization.ps1` used
  `'Your Organization IT Service Desk'` while `Fix-CurrentVM.ps1` used `'ORG IT Service Desk'`.
  Both now use the repo-canonical `ORG` token, so the documented "grep for `ORG`" customization
  sweep catches it.

### Explicitly NOT in this release

- `AuditMode/Apply-SecurityBaseline.ps1` is **still not shipped**. All CIS / VBS / HVCI / Credential
  Guard hardening referenced in `AuditMode/README.md` remains roadmap-only — see `ROADMAP.md`
  (Security, v2.6). Nothing here changes that status.
- Per-script internal doc-control stamps (`WIN11-GOLDIMG-001 v2.3`/`v2.4` etc.) were left untouched;
  they track document revisions, not the repo release version.

---

## v2.4 - Closing notes for the v2.x image line

> **Naming note:** this entry predates the script rename to the `01-` → `11-` sequential,
> verb-first convention used elsewhere in this repo (e.g. `06-BuildOEM.ps1` below is now
> `10-Build-OemLayer.ps1`). Kept as-is for historical accuracy — it documents the actual
> investigation as it happened. See `Scripts/README.md` for the current names.

This release closes the v2.x line: not a feature expansion, but a documented, root-caused fix for
a branding bug plus retirement of a dead code path. Keeping this as a worked example because the
root-cause analysis below is the kind of thing that's genuinely useful to read before you hit the
same class of bug yourself (a producer/consumer path mismatch between two scripts that never
talked to each other).

---

## 1. What v2.4 is

Closing release of the current image line. Not a feature expansion. Three things:

1. Fixes the branding failure (lock screen + wallpaper not applying) at the **real** root cause, confirmed from the deployed-build logs.
2. Retires the OEM logo (it never rendered on Win11).
3. Consolidates the validated v2.3 work into one documented baseline.

Deferred to v3.0: orchestrator script, audit-mode baseline automation, PDF/Adobe association decision.

---

## 2. Branding failure - root cause (corrected, evidence-based)

### Symptom
Drivers and OEM text apply correctly. Desktop wallpaper and lock screen do **not** load.

### Root cause - a path mismatch inside the build contract
Two files disagreed on where branding lives. Confirmed from `06-BuildOEM-APPLY-20260529-155901.log`:

| File | Path it uses | Evidence |
|---|---|---|
| `10-Build-OemLayer.ps1` (producer) | stages JPGs to `C:\Windows\Web\Wallpaper\CompanyBrand\` | log: `Copied Wallpaper: ... -> ...\$OEM$\$$\Web\Wallpaper\CompanyBrand\Wallpaper.jpg` |
| `SetupComplete.cmd` (consumer) | reads JPGs from `C:\Windows\Web\ORG\` (`BRANDROOT`) | `set "BRANDROOT=%SystemRoot%\Web\ORG"` |

At runtime both `WALLSRC` and `LOCKSRC` resolve to a folder that does not exist. TASK 2 and TASK 3 each hit their `if not exist` guard, log ERROR, and skip. Result: **both** wallpaper and lock screen blank, while everything that does not read that path (drivers, OEM text) works. That matches the observed symptom exactly.

### Second, compounding bug
In the deployed `SetupComplete.cmd`, `DEFWALL` had been set to `%BRANDROOT%\Wallpaper.jpg` - identical to `WALLSRC`. The img0 overwrite (`copy /y "%WALLSRC%" "%DEFWALL%"`) therefore copied the file onto itself. `img0.jpg` was never replaced even when the source existed.

### Earlier theories that were WRONG
Windows Spotlight and the `HKU\.DEFAULT` target were proposed as causes before the logs were available. The logs disprove both: the script never got past the file-existence check, so neither the lock screen logic nor the wallpaper logic ever executed. (Spotlight-disable and the Default-hive write are still kept as correct hardening - they just were not the cause.)

### Fix (minimal, change the consumer not the producer)
06 is validated and the JPGs land correctly. So only `SetupComplete.cmd` is corrected:

```
set "BRANDROOT=%SystemRoot%\Web\Wallpaper\CompanyBrand"        (was %SystemRoot%\Web\ORG)
set "DEFWALL=%SystemRoot%\Web\Wallpaper\Windows\img0.jpg"   (was %BRANDROOT%\Wallpaper.jpg)
```

`BRANDROOT` now matches what 06 produces; `DEFWALL` now points at the real OS default so the img0 overwrite is meaningful. The contract comment block was updated to the real path. One file changed for the branding fix.

### Design decision (flip if you disagree)
- Wallpaper = changeable default (img0 overwrite + Default hive).
- Lock screen = enforced (Spotlight disabled, then PersonalizationCSP).

---

## 3. OEM logo - retired

Confirmed by observation: logo configured, not shown in Settings > About. The OEM logo bitmap was a legacy System Control Panel feature; Win11's modern Settings surfaces the OEM text fields but not the logo bitmap. Retired:

- `10-Build-OemLayer.ps1` Step 4 no longer stages `OEMLogo.bmp` (and drops it from the verification list).
- `SetupComplete.cmd` TASK 4 already deletes any stale `Logo` value and writes text fields only.
- Constraint **C8 (OEMLogo 24-bit BMP) is retired**; the `OEM-Template\` README should drop the OEMLogo requirement.

The `OEMLogo.bmp` asset is left in `OEM-Template\` (harmless, unused) rather than deleted.

---

## 4. Changelog v2.3 -> v2.4

| Area | v2.3 | v2.4 |
|---|---|---|
| Branding path | consumer (`Web\ORG`) != producer (`Web\Wallpaper\CompanyBrand`) - silent skip | aligned to `Web\Wallpaper\CompanyBrand`; both files agree |
| img0 overwrite | DEFWALL == WALLSRC (self-copy no-op) | DEFWALL = real `img0.jpg` |
| OEM logo | staged + Logo value set, never rendered | retired in 06 and SetupComplete; C8 retired |
| 06 mount check | scoped to `E:\WimMount` (already correct in this build) | unchanged |
| Docs | no diagrams | 3 Mermaid diagrams added |

---

## 5. Canonical script line (verified against the uploaded ZIP)

| Order | Script | Modifies state |
|---|---|---|
| 00 | `01-Unblock-Scripts.ps1` | No |
| 01 | `02-Extract-Iso.ps1` | Yes |
| 02 | `03-Initialize-BuildEnvironment.ps1` | No |
| 03 | `04-Remove-ProvisionedApps.ps1` | Yes |
| 03a | `Diagnostics\Diagnose-AppxAndCapabilities.ps1` | No |
| 03b | `05-Remove-SystemApps.ps1` | Yes |
| 04 | `06-Remove-OneDrive.ps1` | Yes |
| 04b | `07-Enable-DotNet35.ps1` | Yes |
| 04c | `08-Import-DefaultAppAssociations.ps1` | Yes |
| 05 | `09-Dismount-Image.ps1` | Yes |
| 06 | `10-Build-OemLayer.ps1` | Yes |
| 07 | `11-Build-Iso.ps1` | Yes |

Helper/diagnostic files in `Scripts\`: `Diagnostics\Diagnose-Removal.ps1`, `06-BuildOEM-CMTrace-Snippet.ps1`, `07-RebuildISO-Autounattend-Snippet.ps1`. Naming is consistent; no renumbering required for v2.4.

---

## 6. Open items carried to v3.0

| Item | Disposition |
|---|---|
| Orchestrator script (single-run 00-07) | v3.0 |
| `AuditMode\Apply-SecurityBaseline.ps1` validation on reference VM | v3.0 |
| PDF / Adobe Reader default association | DECISION PENDING - your call; conflicting artifacts exist |
| `unattend\` build (Windows SIM) | operational prerequisite |
| SetupComplete support fields | now populated with your org's live values; verify before production |
| GPO P1: VBS/HVCI/CG disabled by GPP Registry in `Windows-11-Computers` | domain GPO remediation - gates production, not an image change |
| Corporate WLAN server cert validation disabled | domain GPO fix |

---

## 7. Architecture diagrams

### 7.1 Build pipeline and WIM mount lifecycle

```mermaid
flowchart TD
    Start(["Operator on build server"]) --> S00["00 Unblock and Prep<br/>strip MOTW, check mount target"]
    S00 --> S01["01 Extract ISO<br/>mount ISO, robocopy, clear read-only"]
    S01 --> S02["02 Setup Build Environment<br/>verify layout, ADK, tools"]
    S02 --> S03["03 Offline Servicing<br/>MOUNT WIM, remove AppX + capabilities"]
    S03 --> S03b["03b Remove System Components<br/>SystemApp folders offline"]
    S03b --> S04["04 Remove OneDrive<br/>+ reinstall-suppression keys"]
    S04 --> S04b["04b Enable .NET 3.5<br/>offline DISM"]
    S04b --> S04c["04c Import Default Associations<br/>offline DISM"]
    S04c --> S05["05 Dismount and Commit<br/>DISMOUNT WIM -Save"]
    S05 --> S06["06 Build OEM<br/>OEM tree: drivers, branding, SetupComplete"]
    S06 --> S07["07 Rebuild ISO<br/>oscdimg bootable UEFI + SHA256 manifest"]
    S07 --> Out(["Win11_25H2_Custom.iso + manifest"])

    subgraph MOUNTED["WIM mounted at E:\WimMount"]
        S03
        S03b
        S04
        S04b
        S04c
    end
```
*Diagram shows: the 00-07 pipeline, with offline-servicing scripts grouped inside the WIM mount lifecycle (mounted by 03, committed by 05).*

### 7.2 $OEM$ delivery mapping (corrected branding path)

```mermaid
graph LR
    subgraph ISO["Build media: sources OEM tree"]
        A["$$ Setup Scripts SetupComplete.cmd"]
        B["$$ Web Wallpaper CompanyBrand Wallpaper.jpg"]
        C["$$ Web Wallpaper CompanyBrand LockScreen.jpg"]
        D["$1 Drivers .inf trees"]
    end
    subgraph TARGET["Target machine after Setup"]
        A2["C:\Windows\Setup\Scripts\SetupComplete.cmd"]
        B2["C:\Windows\Web\Wallpaper\CompanyBrand\Wallpaper.jpg"]
        C2["C:\Windows\Web\Wallpaper\CompanyBrand\LockScreen.jpg"]
        D2["C:\Drivers\ .inf trees"]
    end
    A -->|"$$ = WINDIR"| A2
    B -->|"$$ = WINDIR"| B2
    C -->|"$$ = WINDIR"| C2
    D -->|"$1 = system drive"| D2
    A2 -->|reads at first boot| B2
    A2 -->|reads at first boot| C2
    A2 -->|DevicePath scan| D2
```
*Diagram shows: producer (06) and consumer (SetupComplete) now agree on the CompanyBrand branding path - the fix that resolves the failure.*

### 7.3 SetupComplete.cmd branding flow (after fix)

```mermaid
flowchart TD
    Run(["SetupComplete.cmd runs as SYSTEM<br/>before OOBE"]) --> T1["TASK 1: DevicePath + pnputil scan"]
    T1 --> T2{"Wallpaper source present?<br/>(now resolves - path fixed)"}
    T2 -->|No| T2skip["Log ERROR, skip"]
    T2 -->|Yes| T2a["Overwrite real img0.jpg<br/>takeown + icacls + copy"]
    T2a --> T2b["Set Default NTUSER.DAT hive<br/>Wallpaper + style"]
    T2b --> T3{"Lock screen source present?"}
    T2skip --> T3
    T3 -->|No| T3skip["Log ERROR, skip"]
    T3 -->|Yes| T3a["Disable Windows Spotlight"]
    T3a --> T3b["PersonalizationCSP<br/>LockScreenImagePath + Status=1"]
    T3b --> T4["TASK 4: OEM text fields<br/>(Logo deleted - retired)"]
    T3skip --> T4
    T4 --> T5["TASK 5: sanity checks + log"]
    T5 --> Done(["exit /b 0"])
```
*Diagram shows: with the path corrected, both source checks now pass, so wallpaper and lock screen logic actually executes.*

---

## 8. Validation step before sign-off

Re-run the cycle and confirm on a fresh deploy:

1. `06` apply log shows branding copied to `...\Web\Wallpaper\CompanyBrand\` (already confirmed).
2. After OOBE, check `%SystemRoot%\Temp\SetupComplete.log` shows `[TASK 2] img0.jpg overwritten OK` and `[TASK 3] Lock screen set OK` (not ERROR/skip).
3. New user profile shows your branded wallpaper; lock screen shows your branded lock screen image; Settings > About shows OEM text and no logo.

If TASK 2/3 still log ERROR, the JPGs are not at `C:\Windows\Web\Wallpaper\CompanyBrand\` on the target - check the ISO was rebuilt by 07 after 06 ran.
