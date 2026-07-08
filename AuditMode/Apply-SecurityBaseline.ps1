#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Image Builder - Apply security hardening baseline (v2.6)
    Runs on the reference VM in audit mode, BEFORE Sysprep.

.DESCRIPTION
    Fills the gap this repo has documented since v2.4 (see ARCHITECTURE.md
    Known gaps, ROADMAP.md v2.6 Security section, AuditMode/README.md): a
    hardening step that runs G1 (baseline compliance) before the reference
    VM is captured. Three layers, each independently toggleable via
    -SkipTasks:

      1. Microsoft Security Compliance Toolkit baseline, applied locally via
         LGPO.exe against the curated Machine-/User-image-baseline.txt files
         (see LGPO/README.md, SCT/README.md) - IF those files have been
         staged. Warns and continues (does not fail the run) if they haven't,
         since GPO-Backup/LGPO/SCT are documented as operator-populated and
         empty by default.
      2. A curated subset of CIS-Benchmark-aligned registry hardening (SMBv1,
         LLMNR, AutoRun, UAC, guest account, anonymous SAM enumeration,
         WDigest, LSA protection, PowerShell script block logging,
         SmartScreen, legacy TLS/SSL protocols).
      3. VBS / HVCI / Credential Guard, Defender ASR rule deployment, and a
         BitLocker *policy* baseline.

    NOT done here: actually encrypting the reference VM's drive
    (Enable-BitLocker). This machine gets Sysprep'd and captured as a WIM -
    an encrypted reference VM would ship BitLocker metadata into the
    captured image, which is wrong. Task 18 below only writes the FVE policy
    registry values that make BitLocker behave correctly once the DEPLOYED
    machine (not this reference VM) actually encrypts - either via your
    existing domain GPO or a separate MDT/Intune step, same division of
    labor already documented for Defaults/ and GPO-Backup/.

    Registry values for VBS/HVCI/Credential Guard were checked against
    Microsoft Learn (Enable virtualization-based protection of code
    integrity; Configure Credential Guard) at the time this script was
    written. ASR rule GUIDs were checked against Microsoft Learn's ASR rules
    reference. BitLocker FVE policy values are the two most load-bearing,
    well-documented keys (encryption method, AD recovery backup requirement)
    - this is a starting baseline, not full GPO parity; extend
    $BitLockerPolicy below against your current org policy before relying on
    it for compliance sign-off.

.PARAMETER Apply
    Default $false (dry-run). Set $true to execute.

.PARAMETER VerifyOnly
    Re-checks every task's current state and writes
    C:\AuditMode\Logs\HardeningReport-*.txt with a [PASS]/[FAIL] per task,
    matching the AuditMode/README.md Step 5 workflow. Does not change
    anything.

.PARAMETER SkipTasks
    Array of task names (see the Name passed to each Invoke-HardeningTask
    call below) to skip - e.g. -SkipTasks 'Credential Guard' if your fleet
    has an incompatible smartcard driver, or 'LSA Protection (RunAsPPL)' for
    the same reason (see ASR rule note on LSASS access below).

.PARAMETER LgpoPath
.PARAMETER MachineBaselinePath
.PARAMETER UserBaselinePath
    Paths to LGPO.exe and the curated baseline text files. Defaults match
    where script 10 now stages LGPO/ and SCT/ on the reference VM (see
    10-Build-OemLayer.ps1 Step 7b).

.NOTES
    Document: WIN11-GOLDIMG-001 v2.6
    Folder:   AuditMode\
    Phase:    Reference VM, audit mode, BEFORE Sysprep (see AuditMode/README.md)
    Order:    This script FIRST, then Apply-PostInstallCustomization.ps1 only
              if SetupComplete.cmd failed silently (see AuditMode/README.md).

    VBS/HVCI/Credential Guard require a reboot to activate (see
    AuditMode/README.md Step 4). Registry-only writes are used throughout
    (not the Group Policy editor) specifically because they degrade
    gracefully on hardware/firmware that doesn't support a given feature -
    Windows reports the feature as "enabled but not running" rather than
    failing to boot. Locked=0 / LsaCfgFlags=2 (not 1) are used deliberately
    so these can be reverted without UEFI console access if a captured image
    turns out to be incompatible with target hardware.
#>

[CmdletBinding()]
param(
    [bool]$Apply = $false,
    [switch]$VerifyOnly,
    [string]$LgpoPath = 'C:\AuditMode\LGPO\LGPO.exe',
    [string]$MachineBaselinePath = 'C:\AuditMode\LGPO\Machine-image-baseline.txt',
    [string]$UserBaselinePath = 'C:\AuditMode\LGPO\User-image-baseline.txt',
    [string[]]$SkipTasks = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogPath = 'C:\AuditMode\Logs'
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Mode      = if ($VerifyOnly) { 'VERIFY' } elseif ($Apply) { 'APPLY' } else { 'DRYRUN' }
$LogFile   = Join-Path $LogPath "AuditMode-Baseline-$Mode-$Timestamp.log"
$ReportFile = Join-Path $LogPath "HardeningReport-$Timestamp.txt"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $Line -ForegroundColor Red }
        'WARN'  { Write-Host $Line -ForegroundColor Yellow }
        'OK'    { Write-Host $Line -ForegroundColor Green }
        'NEXT'  { Write-Host $Line -ForegroundColor Cyan }
        default { Write-Host $Line }
    }
}

Write-Log "========== Apply-SecurityBaseline (v2.6) - Mode: $Mode =========="

if ($VerifyOnly) {
    # Pending reboot means VBS/HVCI/Credential Guard may show as configured
    # but not yet running - this is expected, not a failure, until reboot.
    $RebootPending = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    if ($RebootPending) {
        Write-Log 'A reboot appears to be pending. VBS/HVCI/Credential Guard results below may show as configured but not running until after reboot.' 'WARN'
    }
}

$script:TaskResults = [System.Collections.Generic.List[object]]::new()

function Invoke-HardeningTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Test,
        [Parameter(Mandatory)][scriptblock]$ApplyAction
    )

    if ($SkipTasks -contains $Name) {
        Write-Log "SKIPPED (-SkipTasks): $Name" 'WARN'
        return
    }

    if ($VerifyOnly) {
        try {
            $result = & $Test
        } catch {
            $result = @{ Pass = $false; Detail = "Verify check threw: $_" }
        }
        $status = if ($result.Pass) { 'PASS' } else { 'FAIL' }
        Write-Log "[$status] $Name - $($result.Detail)" $(if ($result.Pass) { 'OK' } else { 'ERROR' })
        $script:TaskResults.Add([pscustomobject]@{ Task = $Name; Status = $status; Detail = $result.Detail })
        return
    }

    if (-not $Apply) {
        Write-Log "[DRY-RUN] Would apply: $Name"
        return
    }

    try {
        & $ApplyAction
        Write-Log "APPLIED: $Name" 'OK'
    } catch {
        Write-Log "FAILED: $Name - $_" 'ERROR'
    }
}

function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Test-RegistryValue {
    param([string]$Path, [string]$Name, $Expected)
    if (-not (Test-Path $Path)) { return @{ Pass = $false; Detail = "Key missing: $Path" } }
    $actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $actual) { return @{ Pass = $false; Detail = "Value missing: $Path\$Name" } }
    if ("$actual" -eq "$Expected") {
        return @{ Pass = $true; Detail = "$Path\$Name = $actual" }
    }
    return @{ Pass = $false; Detail = "$Path\$Name = $actual (expected $Expected)" }
}

# ==========================================================================
# GROUP 1 - Microsoft Security Compliance Toolkit baseline via LGPO.exe
# ==========================================================================
Write-Log ''
Write-Log '----- Group 1: SCT / LGPO baseline -----'

Invoke-HardeningTask -Name 'SCT baseline - Machine policy (LGPO.exe)' `
    -Test {
        if (-not (Test-Path $LgpoPath))            { return @{ Pass = $false; Detail = "LGPO.exe not staged at $LgpoPath - see LGPO/README.md" } }
        if (-not (Test-Path $MachineBaselinePath))  { return @{ Pass = $false; Detail = "Baseline file not staged at $MachineBaselinePath - see LGPO/README.md" } }
        $marker = Join-Path $LogPath '.machine-baseline-applied'
        if (Test-Path $marker) { return @{ Pass = $true; Detail = "Applied at $((Get-Item $marker).LastWriteTime) - see LGPO.exe log for content detail" } }
        return @{ Pass = $false; Detail = 'LGPO.exe and baseline file present but no record of a successful apply (marker file missing)' }
    } `
    -ApplyAction {
        if (-not (Test-Path $LgpoPath) -or -not (Test-Path $MachineBaselinePath)) {
            Write-Log "Skipping machine SCT baseline - LGPO.exe or $MachineBaselinePath not staged (see LGPO/README.md, SCT/README.md)" 'WARN'
            return
        }
        $out = & $LgpoPath /t $MachineBaselinePath 2>&1
        $out | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "LGPO.exe exited $LASTEXITCODE applying machine baseline" }
        New-Item -Path (Join-Path $LogPath '.machine-baseline-applied') -ItemType File -Force | Out-Null
    }

Invoke-HardeningTask -Name 'SCT baseline - User policy (LGPO.exe)' `
    -Test {
        if (-not (Test-Path $LgpoPath))         { return @{ Pass = $false; Detail = "LGPO.exe not staged at $LgpoPath - see LGPO/README.md" } }
        if (-not (Test-Path $UserBaselinePath)) { return @{ Pass = $false; Detail = "Baseline file not staged at $UserBaselinePath - see LGPO/README.md" } }
        $marker = Join-Path $LogPath '.user-baseline-applied'
        if (Test-Path $marker) { return @{ Pass = $true; Detail = "Applied at $((Get-Item $marker).LastWriteTime) - see LGPO.exe log for content detail" } }
        return @{ Pass = $false; Detail = 'LGPO.exe and baseline file present but no record of a successful apply (marker file missing)' }
    } `
    -ApplyAction {
        if (-not (Test-Path $LgpoPath) -or -not (Test-Path $UserBaselinePath)) {
            Write-Log "Skipping user SCT baseline - LGPO.exe or $UserBaselinePath not staged (see LGPO/README.md, SCT/README.md)" 'WARN'
            return
        }
        $out = & $LgpoPath /t $UserBaselinePath 2>&1
        $out | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "LGPO.exe exited $LASTEXITCODE applying user baseline" }
        New-Item -Path (Join-Path $LogPath '.user-baseline-applied') -ItemType File -Force | Out-Null
    }

# ==========================================================================
# GROUP 2 - CIS-Benchmark-aligned registry hardening
# ==========================================================================
Write-Log ''
Write-Log '----- Group 2: CIS-aligned registry hardening -----'

Invoke-HardeningTask -Name 'UAC - Admin Approval Mode + secure desktop prompt' `
    -Test {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $a = Test-RegistryValue -Path $p -Name 'EnableLUA' -Expected 1
        $b = Test-RegistryValue -Path $p -Name 'ConsentPromptBehaviorAdmin' -Expected 2
        $c = Test-RegistryValue -Path $p -Name 'PromptOnSecureDesktop' -Expected 1
        @{ Pass = ($a.Pass -and $b.Pass -and $c.Pass); Detail = "$($a.Detail); $($b.Detail); $($c.Detail)" }
    } `
    -ApplyAction {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Set-RegistryValue -Path $p -Name 'EnableLUA' -Value 1
        Set-RegistryValue -Path $p -Name 'ConsentPromptBehaviorAdmin' -Value 2
        Set-RegistryValue -Path $p -Name 'PromptOnSecureDesktop' -Value 1
    }

Invoke-HardeningTask -Name 'Disable SMBv1' `
    -Test {
        $r = Test-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -Expected 0
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction SilentlyContinue
        $featureOff = (-not $feature) -or ($feature.State -eq 'Disabled')
        @{ Pass = ($r.Pass -and $featureOff); Detail = "$($r.Detail); SMB1Protocol feature: $(if ($feature) { $feature.State } else { 'not present' })" }
    } `
    -ApplyAction {
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -Value 0
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction SilentlyContinue
        if ($feature -and $feature.State -ne 'Disabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop | Out-Null
        }
    }

Invoke-HardeningTask -Name 'Disable LLMNR' `
    -Test { Test-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Expected 0 } `
    -ApplyAction { Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0 }

Invoke-HardeningTask -Name 'Disable AutoRun/AutoPlay (all drive types)' `
    -Test { Test-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Expected 255 } `
    -ApplyAction { Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Value 255 }

Invoke-HardeningTask -Name 'Disable local Guest account' `
    -Test {
        $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
        if (-not $guest) { return @{ Pass = $true; Detail = 'Guest account does not exist' } }
        @{ Pass = (-not $guest.Enabled); Detail = "Guest.Enabled = $($guest.Enabled)" }
    } `
    -ApplyAction {
        $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
        if ($guest -and $guest.Enabled) { Disable-LocalUser -Name 'Guest' }
    }

Invoke-HardeningTask -Name 'Restrict anonymous SAM/share enumeration' `
    -Test {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        $a = Test-RegistryValue -Path $p -Name 'RestrictAnonymousSAM' -Expected 1
        $b = Test-RegistryValue -Path $p -Name 'RestrictAnonymous' -Expected 1
        @{ Pass = ($a.Pass -and $b.Pass); Detail = "$($a.Detail); $($b.Detail)" }
    } `
    -ApplyAction {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        Set-RegistryValue -Path $p -Name 'RestrictAnonymousSAM' -Value 1
        Set-RegistryValue -Path $p -Name 'RestrictAnonymous' -Value 1
    }

Invoke-HardeningTask -Name 'Disable WDigest plaintext credential caching' `
    -Test { Test-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Expected 0 } `
    -ApplyAction { Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 0 }

Invoke-HardeningTask -Name 'LSA Protection (RunAsPPL)' `
    -Test { Test-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RunAsPPL' -Expected 1 } `
    -ApplyAction {
        # Compatibility note (same class of issue Microsoft documents for the
        # "Block credential stealing from LSASS" ASR rule below): third-party
        # smartcard drivers or AV that load into the LSA can be incompatible.
        # Skip via -SkipTasks 'LSA Protection (RunAsPPL)' if that applies to
        # your fleet.
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RunAsPPL' -Value 1
    }

Invoke-HardeningTask -Name 'PowerShell Script Block Logging' `
    -Test { Test-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name 'EnableScriptBlockLogging' -Expected 1 } `
    -ApplyAction { Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name 'EnableScriptBlockLogging' -Value 1 }

Invoke-HardeningTask -Name 'SmartScreen for Explorer (Block mode)' `
    -Test {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        $a = Test-RegistryValue -Path $p -Name 'EnableSmartScreen' -Expected 1
        $b = Test-RegistryValue -Path $p -Name 'ShellSmartScreenLevel' -Expected 'Block'
        @{ Pass = ($a.Pass -and $b.Pass); Detail = "$($a.Detail); $($b.Detail)" }
    } `
    -ApplyAction {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Set-RegistryValue -Path $p -Name 'EnableSmartScreen' -Value 1
        Set-RegistryValue -Path $p -Name 'ShellSmartScreenLevel' -Value 'Block' -Type String
    }

Invoke-HardeningTask -Name 'Disable legacy TLS/SSL protocols (SSL 2.0/3.0, TLS 1.0/1.1)' `
    -Test {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
        $protocols = @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')
        $fails = @()
        foreach ($proto in $protocols) {
            foreach ($side in @('Server', 'Client')) {
                $p = "$base\$proto\$side"
                $r = Test-RegistryValue -Path $p -Name 'Enabled' -Expected 0
                if (-not $r.Pass) { $fails += "$proto/$side" }
            }
        }
        @{ Pass = ($fails.Count -eq 0); Detail = if ($fails.Count -eq 0) { 'All disabled' } else { "Still enabled: $($fails -join ', ')" } }
    } `
    -ApplyAction {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
        $protocols = @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')
        foreach ($proto in $protocols) {
            foreach ($side in @('Server', 'Client')) {
                $p = "$base\$proto\$side"
                Set-RegistryValue -Path $p -Name 'Enabled' -Value 0
                Set-RegistryValue -Path $p -Name 'DisabledByDefault' -Value 1
            }
        }
    }

Invoke-HardeningTask -Name 'Local account policy - min password length + lockout' `
    -Test {
        $out = & net accounts 2>&1
        $minLen = ($out | Select-String 'Minimum password length' | ForEach-Object { ($_ -split ':\s*')[-1].Trim() })
        $lockout = ($out | Select-String 'Lockout threshold' | ForEach-Object { ($_ -split ':\s*')[-1].Trim() })
        $pass = ($minLen -as [int]) -ge 14 -and ($lockout -ne 'Never' -and ($lockout -as [int]) -le 5 -and ($lockout -as [int]) -gt 0)
        @{ Pass = $pass; Detail = "Minimum password length=$minLen, Lockout threshold=$lockout" }
    } `
    -ApplyAction {
        & net accounts /minpwlen:14 /lockoutthreshold:5 /lockoutduration:15 /lockoutwindow:15 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "net accounts exited $LASTEXITCODE" }
    }

# ==========================================================================
# GROUP 3 - VBS / HVCI / Credential Guard
# ==========================================================================
Write-Log ''
Write-Log '----- Group 3: VBS / HVCI / Credential Guard (reboot required to activate) -----'

Invoke-HardeningTask -Name 'VBS + Memory Integrity (HVCI)' `
    -Test {
        $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
        $hvci = "$dg\Scenarios\HypervisorEnforcedCodeIntegrity"
        $a = Test-RegistryValue -Path $dg -Name 'EnableVirtualizationBasedSecurity' -Expected 1
        $b = Test-RegistryValue -Path $hvci -Name 'Enabled' -Expected 1
        @{ Pass = ($a.Pass -and $b.Pass); Detail = "$($a.Detail); $($b.Detail). Runtime status: Get-CimInstance Win32_DeviceGuard (requires reboot to reflect)" }
    } `
    -ApplyAction {
        $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
        Set-RegistryValue -Path $dg -Name 'EnableVirtualizationBasedSecurity' -Value 1
        Set-RegistryValue -Path $dg -Name 'RequirePlatformSecurityFeatures' -Value 1
        Set-RegistryValue -Path $dg -Name 'Locked' -Value 0
        $hvci = "$dg\Scenarios\HypervisorEnforcedCodeIntegrity"
        Set-RegistryValue -Path $hvci -Name 'Enabled' -Value 1
        Set-RegistryValue -Path $hvci -Name 'Locked' -Value 0
    }

Invoke-HardeningTask -Name 'Credential Guard' `
    -Test {
        $r = Test-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -Expected 2
        @{ Pass = $r.Pass; Detail = "$($r.Detail). Runtime status: (Get-CimInstance Win32_DeviceGuard).SecurityServicesRunning (requires reboot to reflect)" }
    } `
    -ApplyAction {
        # LsaCfgFlags=2 (enabled WITHOUT UEFI lock) is deliberate - see .NOTES.
        Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -Value 2
    }

# ==========================================================================
# GROUP 4 - Microsoft Defender Attack Surface Reduction rules
# ==========================================================================
Write-Log ''
Write-Log '----- Group 4: Defender Attack Surface Reduction (ASR) rules -----'

# GUIDs verified against Microsoft Learn's ASR rules reference. Excludes
# "Block Webshell creation for Servers" (Exchange-server-only, not
# applicable to a Win11 workstation image).
$AsrRules = [ordered]@{
    '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Block abuse of exploited vulnerable signed drivers'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Block credential stealing from LSASS'
    'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Block persistence through WMI event subscription'
    '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Block Adobe Reader from creating child processes'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block all Office applications from creating child processes'
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email client and webmail'
    '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executable files unless prevalence/age/trusted-list criteria met'
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
    'd3e037e1-3eb8-44c8-a917-57927947596d' = 'Block JavaScript/VBScript from launching downloaded executable content'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office applications from creating executable content'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office applications from injecting code into other processes'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication apps from creating child processes'
    'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'Block process creations from PSExec and WMI commands'
    '33ddedf1-c6e0-47cb-833e-de6133960387' = 'Block rebooting machine in Safe Mode'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted and unsigned processes that run from USB'
    'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'Block use of copied or impersonated system tools'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
    'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'Use advanced protection against ransomware'
}

Invoke-HardeningTask -Name 'Defender ASR rules (Block mode)' `
    -Test {
        $pref = Get-MpPreference -ErrorAction SilentlyContinue
        if (-not $pref) { return @{ Pass = $false; Detail = 'Get-MpPreference unavailable (Defender not present/running)' } }
        $ids = @($pref.AttackSurfaceReductionRules_Ids)
        $actions = @($pref.AttackSurfaceReductionRules_Actions)
        $configured = @{}
        for ($i = 0; $i -lt $ids.Count; $i++) { $configured[$ids[$i].ToLowerInvariant()] = $actions[$i] }
        $missing = @()
        foreach ($guid in $AsrRules.Keys) {
            # 1 = Block
            if ($configured[$guid] -ne 1) { $missing += $AsrRules[$guid] }
        }
        @{ Pass = ($missing.Count -eq 0); Detail = if ($missing.Count -eq 0) { "$($AsrRules.Count)/$($AsrRules.Count) rules set to Block" } else { "Not in Block mode: $($missing -join '; ')" } }
    } `
    -ApplyAction {
        $ids = @($AsrRules.Keys)
        $actions = @($ids | ForEach-Object { 'Enabled' })
        Set-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions
    }

# ==========================================================================
# GROUP 5 - BitLocker policy baseline (policy only - does NOT encrypt this VM)
# ==========================================================================
Write-Log ''
Write-Log '----- Group 5: BitLocker policy baseline (policy only, no encryption here) -----'

Invoke-HardeningTask -Name 'BitLocker FVE policy - encryption method + AD recovery backup' `
    -Test {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
        $a = Test-RegistryValue -Path $p -Name 'EncryptionMethodWithXtsOs' -Expected 7
        @{ Pass = $a.Pass; Detail = "$($a.Detail). This VM is NOT encrypted by this script - policy only, see .NOTES / Group 5 header." }
    } `
    -ApplyAction {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
        # XTS-AES 256-bit for OS drives.
        Set-RegistryValue -Path $p -Name 'EncryptionMethodWithXtsOs' -Value 7
        # OSRequireActiveDirectoryBackup is deliberately left unset here: it
        # forces BitLocker to refuse to encrypt until AD recovery-key backup
        # succeeds, which is correct ONLY if your org backs up recovery keys
        # to on-prem AD DS rather than Entra ID/Intune. Uncomment if that's
        # your model:
        #   Set-RegistryValue -Path $p -Name 'OSRequireActiveDirectoryBackup' -Value 1
    }

# ==========================================================================
# Summary / HardeningReport
# ==========================================================================
Write-Log ''
if ($VerifyOnly) {
    $passCount = ($script:TaskResults | Where-Object { $_.Status -eq 'PASS' }).Count
    $failCount = ($script:TaskResults | Where-Object { $_.Status -eq 'FAIL' }).Count

    $reportLines = @(
        'Windows 11 Image Builder - Hardening Report'
        '============================================'
        "Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Host      : $env:COMPUTERNAME"
        ''
    )
    foreach ($r in $script:TaskResults) {
        $reportLines += "[$($r.Status)] $($r.Task)"
        $reportLines += "       $($r.Detail)"
    }
    $reportLines += ''
    $reportLines += "TOTAL: $passCount PASS, $failCount FAIL (of $($script:TaskResults.Count) checked, $($SkipTasks.Count) skipped)"
    $reportLines | Out-File -FilePath $ReportFile -Encoding UTF8

    Write-Log "========== Verify complete. Report: $ReportFile =========="
    if ($failCount -eq 0) {
        Write-Log "*** ALL CHECKS PASS ($passCount/$($script:TaskResults.Count)) ***" 'OK'
    } else {
        Write-Log "*** $failCount CHECK(S) FAILED - review $ReportFile before proceeding to Sysprep ***" 'ERROR'
    }
} elseif ($Apply) {
    Write-Log '========== Apply complete =========='
    Write-Log '*** Reboot required to activate VBS / HVCI / Credential Guard. ***' 'WARN'
    Write-Log '*** After reboot, run: .\Apply-SecurityBaseline.ps1 -VerifyOnly ***' 'NEXT'
} else {
    Write-Log '========== Dry-run complete =========='
    Write-Log '*** DRY-RUN - no changes made. Re-run with -Apply $true ***' 'WARN'
}
