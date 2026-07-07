@{
    # Used by .github/workflows/validate.yml and locally via:
    #   Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Every script's Write-Log function writes colored console output via
        # Write-Host by design (see any Scripts/*.ps1 Write-Log definition) -
        # ERROR=Red/WARN=Yellow/OK=Green/NEXT=Cyan is the repo-wide convention
        # operators rely on when running these interactively. Write-Output
        # cannot carry per-line color; this is a deliberate choice, not an
        # oversight.
        'PSAvoidUsingWriteHost',

        # Every script in this repo defines its own Write-Log function for the
        # colored, file-plus-console logging convention used throughout (see
        # any Scripts/*.ps1 header). PSScriptAnalyzer's compatibility profile
        # flags this as "overwriting" a built-in Write-Log cmdlet that doesn't
        # actually exist in Windows PowerShell 5.1 or PowerShell 7 - a known
        # false positive against the bundled core-6.1.0-windows compatibility
        # data, not a real collision.
        'PSAvoidOverwritingBuiltInCmdlets',

        # This repo's safety convention is the repo-wide "[switch]$Apply,
        # dry-run by default" pattern (see README.md Quick start / every
        # script's -Apply parameter) rather than -WhatIf/-Confirm via
        # SupportsShouldProcess. Both are valid; enforcing ShouldProcess on
        # top of the existing -Apply gate would be redundant, not safer.
        'PSUseShouldProcessForStateChangingFunctions',

        # Several scripts define nested functions that read script-scope
        # parameters via closure (e.g. AuditMode/Apply-PostInstallCustomization.ps1's
        # Enable-NetFx3 reading $NetFx3SourcePath) - PSScriptAnalyzer's
        # unused-parameter check does not follow closures across function
        # boundaries and flags these as false positives.
        'PSReviewUnusedParameter'
    )
}
