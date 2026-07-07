## What does this change?

<!-- One or two sentences. If it fixes an issue, write "Fixes #123". -->

## Which script(s)?

<!-- e.g. Scripts/06-Remove-OneDrive.ps1, AuditMode/Software/Install-ImageSoftware.ps1 -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation only
- [ ] Refactor (no functional change)

## Checklist

- [ ] Ran with default (dry-run) mode and confirmed no unintended changes
- [ ] Ran with `-Apply` on a test VM/build server, not production
- [ ] Updated the relevant `README.md` if behavior, parameters, or run order changed
- [ ] No hardcoded paths, credentials, tokens, or organization-specific values introduced
- [ ] Logging follows existing conventions (`Write-Log` levels: INFO/WARN/ERROR/OK/NEXT)
- [ ] `ASCII` only — no smart quotes, em-dashes, box-drawing characters, or emoji in script output

## Testing performed

<!-- What did you actually run this against? Windows version, ADK version, dry-run vs apply. -->

## Anything reviewers should look at closely?

<!-- Optional. Flag anything you're unsure about. -->
