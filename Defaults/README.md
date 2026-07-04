# Defaults\

Organisational default configuration files baked into the reference image at Phase 3.4.1.

| File | Destination in image | Source GPO |
|---|---|---|
| `Default_Apps_Windows11.xml` | `C:\ProgramData\ORG\Defaults\` | GPP File (was mis-located in System32) |
| `Corporate_wifi_template.xml` | `C:\ProgramData\ORG\Defaults\` | GPP File (was mis-located in System32) |

**Status:** EMPTY — copy current files from `\\corp.contoso.local\netlogon\` and from `\\corp.contoso.local\SYSVOL\corp.contoso.local\scripts\Corporate_wifi_template.xml`.

**IMPORTANT — Path change vs. current production:** the current Computers GPO copies these to `C:\Windows\System32\`. v2.1 relocates them to `C:\ProgramData\ORG\Defaults\`. The domain GPO Administrative Templates (default-associations path) MUST be updated to reference the new location in the same change window.
