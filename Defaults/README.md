# Defaults\

Intended destination for organisational default configuration files (default-app
associations, Wi-Fi profile) sourced from your domain GPOs.

**Not yet wired into the pipeline.** `03-Initialize-BuildEnvironment.ps1` checks
for these files and logs an informational `NEEDED` line if they're absent, but no
script in `Scripts\01`-`11` or `AuditMode\` currently copies them into the image
or applies the Wi-Fi profile — this folder is a staging placeholder ahead of
that automation, not a live input yet. Tracked as a gap; see `ROADMAP.md`.

Do not confuse `Default_Apps_Windows11.xml` here with
`OEM-Template\OEMDefaultAssociations.xml` — the latter is a different,
already-wired-up file (imported offline by script `08`) that only overrides
the `.log -> CMTrace` file-type association, not general default-app or Wi-Fi
settings.

| File | Intended destination | Source GPO |
|---|---|---|
| `Default_Apps_Windows11.xml` | `C:\ProgramData\ORG\Defaults\` | GPP File (was mis-located in System32) |
| `Corporate_wifi_template.xml` | `C:\ProgramData\ORG\Defaults\` | GPP File (was mis-located in System32) |

**Status:** EMPTY — copy current files from `\\corp.contoso.local\netlogon\` and from `\\corp.contoso.local\SYSVOL\corp.contoso.local\scripts\Corporate_wifi_template.xml`.

**IMPORTANT — Path change vs. current production:** the current Computers GPO copies these to `C:\Windows\System32\`. The intended destination is `C:\ProgramData\ORG\Defaults\` instead. Once the automation to apply these lands, the domain GPO Administrative Templates (default-associations path) will need to be updated to reference the new location in the same change window.
