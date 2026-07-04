# Contributing

Thank you for contributing to Win11-Golden-Image-Builder.

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
* SupportsShouldProcess where appropriate

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
