# SCT\ — Microsoft Security Compliance Toolkit

**Status:** EMPTY — populate before the reference-VM hardening step (Phase 2, see
`ARCHITECTURE.md` §4). Consumed by `AuditMode\Apply-SecurityBaseline.ps1` (v2.6).
Staged into the built ISO automatically by `10-Build-OemLayer.ps1` (Step 7b) once
populated — see `AuditMode/README.md`.

## What to download

Download the Microsoft Security Compliance Toolkit from:
https://www.microsoft.com/en-us/download/details.aspx?id=55319

Extract the **Windows 11 v25H2 Security Baseline** package into this folder. Expected substructure after extraction:

```
SCT\
└── Windows-11-v25H2-Security-Baseline\
    ├── Documentation\
    ├── GP Reports\
    ├── GPOs\
    ├── Scripts\
    │   ├── Baseline-LocalInstall.ps1
    │   └── LGPO.exe
    └── Templates\
```

`AuditMode\Apply-SecurityBaseline.ps1` (v2.6) does not invoke `Baseline-LocalInstall.ps1`
directly - it applies the curated `LGPO\*-image-baseline.txt` files (see `LGPO/README.md`)
via `LGPO.exe`. `Baseline-LocalInstall.ps1` is left here as the source Microsoft ships the
baseline `.txt`/`.pol` content in, and is useful to run by hand if you want the full,
uncurated SCT baseline rather than the curated `-image-baseline.txt` subset.
