# LGPO\ — Local Group Policy Object tooling

**Status:** EMPTY — populate before the reference-VM hardening step (Phase 2, see
`ARCHITECTURE.md` §4). Consumed by `AuditMode\Apply-SecurityBaseline.ps1` (v2.6).
Staged into the built ISO automatically by `10-Build-OemLayer.ps1` (Step 7b) once
populated — see `AuditMode/README.md`.

LGPO.exe ships inside the Microsoft Security Compliance Toolkit (see `..\SCT\`).
Copy LGPO.exe here for convenience and place the curated text-format policy files derived from the ORG domain GPO backups:

```
LGPO\
├── LGPO.exe                       # From SCT\Windows-11-v25H2-Security-Baseline\Scripts\
├── Machine-from-backup.txt        # Output of LGPO.exe /parse against Computers GPO Registry.pol
├── Machine-image-baseline.txt     # Curated subset per Appendix F (BAKE rows only)
├── User-from-backup.txt           # Output of LGPO.exe /parse against Users GPO Registry.pol
└── User-image-baseline.txt        # Curated subset per Appendix F (BAKE rows only)
```

The `-image-baseline.txt` files are applied on the reference VM by
`AuditMode\Apply-SecurityBaseline.ps1`, which runs the equivalent of:
```powershell
.\LGPO.exe /t Machine-image-baseline.txt
.\LGPO.exe /t User-image-baseline.txt
```
