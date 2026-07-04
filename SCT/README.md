# SCT\ — Microsoft Security Compliance Toolkit

**Status:** EMPTY — populate before Phase 3.

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

Used in Phase 3.3.2 via `.\Baseline-LocalInstall.ps1 -Win11NonDomainJoined`.
