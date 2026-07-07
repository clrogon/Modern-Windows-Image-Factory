# Roadmap

## Version 2.6 - Delivered

See `CHANGELOG.md` (v2.6 entry) for the full writeup. Summary:

### Image Engineering

* Driver injection automation - `Scripts/12-Inject-Drivers.ps1`
* Dynamic language pack integration - `Scripts/13-Add-LanguagePacks.ps1`
* Features on Demand automation - `Scripts/14-Add-FeaturesOnDemand.ps1`
* Optional Microsoft Store restoration - `Scripts/15-Restore-MicrosoftStore.ps1`

### Security

* CIS Benchmark automation - `AuditMode/Apply-SecurityBaseline.ps1` (curated registry-hardening
  subset; see the script's own header for exactly what's covered and what isn't)
* Defender ASR rule deployment - same script, full current 18-rule set
* BitLocker baseline integration - same script, FVE policy registry only (does not encrypt the
  reference VM - see the script's header for why)
* Security compliance validation reports - same script's `-VerifyOnly` mode, `HardeningReport-*.txt`

### Automation

* GitHub Actions validation pipeline - `.github/workflows/validate.yml`
* PSScriptAnalyzer integration - `PSScriptAnalyzerSettings.psd1` + the workflow above
* Automated release packaging - `.github/workflows/release.yml`

---

## Version 3.0

### Modern Build Engine

* Configuration-driven builds
* JSON build profiles
* Multiple Windows editions
* ARM64 support

### Platform Engineering

* Golden Image as Code
* Build reproducibility validation
* Artifact versioning
* Build manifest generation

### Cloud Integration

* Azure Image Builder support
* Azure Compute Gallery publishing
* Intune integration packages

---

## Future Vision

Transform the project into a complete Windows Platform Engineering framework supporting:

* Workstations
* Kiosks
* VDI
* Azure Virtual Desktop
* Windows Server
* Cloud-hosted reference images
