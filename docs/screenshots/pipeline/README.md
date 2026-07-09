# Pipeline screenshots

Real captures of the build-server pipeline (`Scripts/01` -> `11`) running against a Windows 11
25H2 build. Embedded in the root `README.md`'s "Pipeline in action" section.

These are **execution** captures (the scripts running in PowerShell) - distinct from the
**outcome** captures in the parent `docs/screenshots/` folder (what a deployed/reference machine
looks like).

| File | Step | Shows |
|---|---|---|
| `01-unblock-scripts.png` | 01 | Unblocking downloaded scripts, execution-policy + runtime-folder checks |
| `02-extract-iso.png` | 02 | Mounting the Enterprise ISO, copy-out, `install.wim` edition index list |
| `03-initialize-buildenvironment.png` | 03 | Folder/required-file checks, ADK/oscdimg discovery |
| `04-remove-provisionedapps.png` | 04 | Offline provisioned-AppX removal (dry-run then `-Apply`, verified removals) |
| `05-remove-systemapps.png` | 05 | SystemApps removal pass |
| `06-remove-onedrive.png` | 06 | Consumer OneDrive removal + reinstall-suppression keys in the offline hive |
| `07-enable-dotnet35.png` | 07 | Enabling .NET Framework 3.5 offline from `sources\sxs` |
| `08-import-defaultappassociations.png` | 08 | Default-app-association import (**not linked in the root README** - its verify step prints the `OEMDefaultAssociations.xml` header; re-link once that header is generic) |
| `09-dismount-image.png` | 09 | Dismount with `-Save`, committing all changes into the WIM |
| `11-build-iso.png` | 11 | Repackaging the bootable ISO + SHA256 manifest |

Step 10 (`10-Build-OemLayer.ps1`) is not yet captured. Add `10-build-oemlayer.png` here and link
it in the root README when you have it.

## Re-capturing

- PNG over JPEG - no compression artifacts on terminal text.
- Crop or sanitize anything host-/org-specific before publishing (internal reference codes,
  owner fields, real support numbers, non-generic paths).
- Keep the `NN-verb-noun.png` naming so the root README links keep working.
