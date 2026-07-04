# unattend\

**Status:** TEMPLATES NEEDED — populate before Phase 3.4.3.

Two answer files used at different stages:

| File | Used by | Stage |
|---|---|---|
| `unattend-reference.xml` | Sysprep on the reference machine | Phase 3.4.3 — Sysprep generalize |
| `unattend-deploy.xml` | MDT on target devices | Per ORG-IT-WIN11-DEP-001 |

**Required elements for `unattend-reference.xml`:**
- OOBE skip pages (EULA, Region, Network)
- Time zone: your target market's Windows time zone ID (example used in the scripts: `Eastern Standard Time`)
- Input locale: your target market's locale (example used in the scripts: `en-US`)
- System locale: `en-US`
- `CopyProfile=true` to baseline the default user profile
- `DoNotCleanTaskbar=true` to preserve curated taskbar layout
- OEM information (logo, support phone, URL) under `OEMInformation`

Build the answer files using Windows System Image Manager (SIM) from the Windows ADK.
