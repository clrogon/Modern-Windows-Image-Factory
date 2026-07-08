# Contributing

Thank you for contributing to Modern Windows Image Factory.

## Contribution Guidelines

### Reporting Issues

When opening an issue, include:

* Windows version
* PowerShell version
* ADK version
* Script name
* Error message
* Relevant logs

### Pull Requests

Before submitting:

* Verify scripts execute successfully.
* Include documentation updates.
* Preserve existing logging conventions.
* Maintain idempotent behavior whenever possible.
* Avoid hard-coded paths.
* Avoid embedding credentials or secrets.

### PowerShell Standards

Preferred practices:

* CmdletBinding()
* Parameter validation
* Try/Catch error handling
* Verbose logging
* Comment-based help
* `-Apply` dry-run-by-default (this repo's chosen convention - see
  `PSScriptAnalyzerSettings.psd1` for why `SupportsShouldProcess` isn't
  additionally required on top of it)

New/changed `.ps1` files are linted by `.github/workflows/validate.yml`
(PSScriptAnalyzer, via `PSScriptAnalyzerSettings.psd1`) on every push and PR.
Run it locally before pushing:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

### Security Requirements

Pull requests must not include:

* Credentials
* Tokens
* Certificates
* VPN secrets
* Internal infrastructure references
* Proprietary software binaries

### Testing

All changes should be tested against:

* Windows 11 Enterprise
* PowerShell 5.1
* Latest supported Windows ADK

Thank you for helping improve the project.
