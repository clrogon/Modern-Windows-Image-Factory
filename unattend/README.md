# unattend\

**Status:** TEMPLATES NEEDED — populate before the reference-VM Sysprep step (Phase 2, see `ARCHITECTURE.md` §4).

Two answer files used at different stages:

| File | Used by | Stage |
|---|---|---|
| `unattend-reference.xml` | Sysprep on the reference machine | Phase 2 (reference VM) — Sysprep `/generalize` step |
| `unattend-deploy.xml` | MDT on target devices | Per ORG-IT-WIN11-DEP-001 |

**Required elements for `unattend-reference.xml`:**
- OOBE skip pages (EULA, Region, Network)
- Time zone: your target market's Windows time zone ID (used elsewhere in this repo:
  `W. Central Africa Standard Time`, Angola)
- Input locale: your target market's locale (used elsewhere in this repo: `pt-AO`)
- System locale: `en-US`
- `CopyProfile=true` to baseline the default user profile
- `DoNotCleanTaskbar=true` to preserve curated taskbar layout
- OEM information (logo, support phone, URL) under `OEMInformation`

Build the answer files using Windows System Image Manager (SIM) from the Windows ADK.
