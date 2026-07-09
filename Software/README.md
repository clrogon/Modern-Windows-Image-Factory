# Software\

**Status:** NOT SHIPPED, OPTIONAL — create as needed before running
`Scripts/15-Restore-MicrosoftStore.ps1` (v2.6).

Expected layout:

```
Software\MicrosoftStore\
├── *.appxbundle or *.msixbundle   (the Store package itself)
├── *.xml                         (its license file)
└── Dependencies\*.appx / *.msix   (framework packages it depends on)
```

Produce that export from a reference machine that still has Store installed
(`Get-AppxPackage -AllUsers Microsoft.WindowsStore` +
`Get-AppxPackageManifest`, or pull the bundle/license/deps from an offline
source) — see the script's header comment for the full procedure.

This is a separate folder from `AuditMode/Software/`, which holds the THICK
build's installer scripts and config (M365 ODT, Adobe Acrobat, etc.) and is
tracked in the repo.
