# SCT\ — Microsoft Security Compliance Toolkit

**Status:** EMPTY — populate before the reference-VM hardening step (Phase 2, see
`ARCHITECTURE.md` §4). Consumed by `AuditMode\Apply-SecurityBaseline.ps1`,
which is **not yet shipped** in this repo — see `ROADMAP.md` (Security, v2.6).

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

Used via `.\Baseline-LocalInstall.ps1 -Win11NonDomainJoined` on the reference VM
(roadmap — see note above).
