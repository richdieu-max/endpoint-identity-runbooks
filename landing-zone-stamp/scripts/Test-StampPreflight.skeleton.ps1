<#
.SYNOPSIS
    SKELETON. Read-only preflight for a landing zone / stamp deployment.

.DESCRIPTION
    Most failed builds fail for reasons that exist before the first resource is
    created: no VM quota, a VM family restricted in the region, a role assignment
    that carries a condition, a guest account that cannot create groups, a
    resource provider that was never registered. This script checks each of
    those as a "gate" and says who has to act to open it.

    It changes nothing. Every live call is a Get-* cmdlet.

    Two ways to run:
      Live    : sign in with Connect-AzAccount, pass -SubscriptionId.
      Offline : pass -FactsFile with facts collected earlier (or the example),
                which is how CI tests the gate logic without a tenant.

.EXAMPLE
    ./Test-StampPreflight.skeleton.ps1 -FactsFile ../examples/preflight-facts.example.json

.EXAMPLE
    Connect-AzAccount -Tenant <tenant-id>
    ./Test-StampPreflight.skeleton.ps1 -SubscriptionId <subscription-id> -VmSize Standard_D2s_v5 -CoresNeeded 2
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId,
    [string] $Location = 'eastus2',
    [string] $VmSize = 'Standard_D2s_v5',
    [int]    $CoresNeeded = 2,
    [string[]] $RequiredProviders = @(
        'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.KeyVault',
        'Microsoft.RecoveryServices', 'Microsoft.OperationalInsights', 'Microsoft.Insights'
    ),
    [string] $FactsFile,
    [string] $OutputPath = './preflight',
    [switch] $FailOnBlocked
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0-skeleton'

# ------------------------------------------------------------------ collect
function Get-LiveFact {
    <# Collects the facts the gates need. Each lookup is isolated: a lookup that
       fails records $null, and its gate reports "Could not check", never a false PASS. #>
    param([string]$SubscriptionId, [string]$Location, [string]$VmSize, [string[]]$RequiredProviders)

    $facts = [ordered]@{
        subscriptionId    = $SubscriptionId
        signedInUserType  = $null
        roles             = @()
        canCreateGroups   = $null
        vmFamily          = $null
        quotaLimit        = $null
        quotaUsed         = $null
        skuRestricted     = $null
        providers         = @()
        encryptionAtHost  = $null
        entraP2           = $null
    }

    Set-AzContext -Subscription $SubscriptionId | Out-Null   # local session only

    try {
        $me = Get-AzADUser -SignedIn
        $facts.signedInUserType = $me.UserType
        $facts.roles = @(Get-AzRoleAssignment -ObjectId $me.Id -Scope "/subscriptions/$SubscriptionId" |
            ForEach-Object { [ordered]@{ role = $_.RoleDefinitionName; scope = $_.Scope; condition = $_.Condition } })
    } catch { Write-Warning "identity lookup failed: $($_.Exception.Message)" }

    try {
        $sku = Get-AzComputeResourceSku -Location $Location | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $VmSize } | Select-Object -First 1
        if ($sku) {
            $facts.vmFamily = $sku.Family
            $facts.skuRestricted = [bool]($sku.Restrictions | Where-Object { $_.ReasonCode -eq 'NotAvailableForSubscription' })
            $usage = Get-AzVMUsage -Location $Location | Where-Object { $_.Name.Value -eq $sku.Family }
            if ($usage) { $facts.quotaLimit = $usage.Limit; $facts.quotaUsed = $usage.CurrentValue }
        }
    } catch { Write-Warning "compute lookup failed: $($_.Exception.Message)" }

    foreach ($ns in $RequiredProviders) {
        try {
            $state = (Get-AzResourceProvider -ProviderNamespace $ns | Select-Object -First 1).RegistrationState
            $facts.providers += [ordered]@{ namespace = $ns; state = $state }
        } catch { $facts.providers += [ordered]@{ namespace = $ns; state = $null } }
    }

    try {
        $facts.encryptionAtHost = (Get-AzProviderFeature -FeatureName EncryptionAtHost -ProviderNamespace Microsoft.Compute).RegistrationState
    } catch { Write-Warning "feature lookup failed: $($_.Exception.Message)" }

    # TODO (full build): canCreateGroups and entraP2 come from Microsoft Graph
    # (directory roles of the signed-in account; subscribedSkus for AAD_PREMIUM_P2).
    [pscustomobject]$facts
}

# ------------------------------------------------------------------ decide
function New-Gate([string]$Id, [string]$Name, [string]$Status, [string]$Detail, [string]$WhoActs) {
    [pscustomobject]@{ Gate = $Id; Check = $Name; Status = $Status; Detail = $Detail; 'Who must act' = $WhoActs }
}

function Get-GateResult {
    <# Pure function: facts in, gates out. No Azure calls, so it is easy to test. #>
    param([Parameter(Mandatory)] $Facts, [int]$CoresNeeded, [string]$VmSize)

    $gates = New-Object System.Collections.Generic.List[object]

    # G1 - a usable role at the subscription
    $buildRoles = @($Facts.roles | Where-Object { $_.role -in @('Owner', 'User Access Administrator') })
    if ($null -eq $Facts.roles) {
        $gates.Add((New-Gate 'G1' 'Owner (or UAA) on the subscription' 'Could not check' 'role lookup failed' 'You'))
    } elseif ($buildRoles.Count -eq 0) {
        $gates.Add((New-Gate 'G1' 'Owner (or UAA) on the subscription' 'BLOCKED' 'no role that can assign roles' 'Subscription owner'))
    } else {
        $gates.Add((New-Gate 'G1' 'Owner (or UAA) on the subscription' 'PASS' (($buildRoles | ForEach-Object role) -join ', ') ''))
    }

    # G2 - that role is not limited by a condition (ABAC). A conditioned Owner
    #      can deploy resources but cannot make the build's own role grants.
    $conditioned = @($buildRoles | Where-Object { $_.condition })
    if ($conditioned.Count -gt 0) {
        $gates.Add((New-Gate 'G2' 'Role assignment has no condition' 'BLOCKED' 'role assignments limited by a condition; build role grants will fail' 'Owner without a condition (re-grant with "allow all roles")'))
    } elseif ($buildRoles.Count -gt 0) {
        $gates.Add((New-Gate 'G2' 'Role assignment has no condition' 'PASS' '' ''))
    }

    # G3 - can create the security groups the build assigns roles to
    if ($null -eq $Facts.canCreateGroups) {
        $detail = if ($Facts.signedInUserType -eq 'Guest') { 'guest account: group creation is usually blocked' } else { 'not checked (Graph)' }
        $gates.Add((New-Gate 'G3' 'Can create Entra ID security groups' 'Could not check' $detail 'Global Administrator, if blocked'))
    } elseif (-not $Facts.canCreateGroups) {
        $gates.Add((New-Gate 'G3' 'Can create Entra ID security groups' 'BLOCKED' 'Azure Owner is not a directory role' 'Global Administrator: create the groups, or grant Groups Administrator for the build'))
    } else {
        $gates.Add((New-Gate 'G3' 'Can create Entra ID security groups' 'PASS' '' ''))
    }

    # G4 - quota for the VM family
    if ($null -eq $Facts.quotaLimit) {
        $gates.Add((New-Gate 'G4' "vCPU quota for $VmSize" 'Could not check' 'family not found in region' 'You'))
    } elseif (($Facts.quotaLimit - $Facts.quotaUsed) -lt $CoresNeeded) {
        $gates.Add((New-Gate 'G4' "vCPU quota for $VmSize" 'BLOCKED' "$($Facts.vmFamily): $($Facts.quotaUsed) of $($Facts.quotaLimit) used, $CoresNeeded needed" 'Subscription owner: file a quota request'))
    } else {
        $gates.Add((New-Gate 'G4' "vCPU quota for $VmSize" 'PASS' "$($Facts.quotaLimit - $Facts.quotaUsed) free" ''))
    }

    # G5 - the size is not capacity-restricted for this subscription
    if ($null -eq $Facts.skuRestricted) {
        $gates.Add((New-Gate 'G5' 'VM size offered in region' 'Could not check' '' 'You'))
    } elseif ($Facts.skuRestricted) {
        $gates.Add((New-Gate 'G5' 'VM size offered in region' 'BLOCKED' "$VmSize restricted for this subscription" 'You: pick a newer family, or request access'))
    } else {
        $gates.Add((New-Gate 'G5' 'VM size offered in region' 'PASS' '' ''))
    }

    # G6 - resource providers registered
    $unregistered = @($Facts.providers | Where-Object { $_.state -ne 'Registered' } | ForEach-Object namespace)
    if ($unregistered.Count -gt 0) {
        $gates.Add((New-Gate 'G6' 'Resource providers registered' 'BLOCKED' ($unregistered -join ', ') 'You (Owner can register)'))
    } else {
        $gates.Add((New-Gate 'G6' 'Resource providers registered' 'PASS' '' ''))
    }

    # G7 - encryption at host feature (the VM template sets it)
    if ($Facts.encryptionAtHost -eq 'Registered') {
        $gates.Add((New-Gate 'G7' 'EncryptionAtHost feature' 'PASS' '' ''))
    } else {
        $gates.Add((New-Gate 'G7' 'EncryptionAtHost feature' 'BLOCKED' "state: $($Facts.encryptionAtHost)" 'You (Owner can register)'))
    }

    # G8 - Entra ID P2 for just-in-time (PIM) role assignments. A warning, not a block:
    #      the build falls back to standing group-based roles and records the risk.
    if ($Facts.entraP2 -eq $true) {
        $gates.Add((New-Gate 'G8' 'Entra ID P2 (for PIM)' 'PASS' '' ''))
    } else {
        $gates.Add((New-Gate 'G8' 'Entra ID P2 (for PIM)' 'WARN' 'no P2: PIM steps will be skipped and logged as a risk' 'System owner: licence decision'))
    }

    $gates
}

# ------------------------------------------------------------------ write
function Write-PreflightEvidence {
    param($Gates, $Facts, [string]$OutputPath, [string]$Mode)
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + 'Z'
    $dir = Join-Path $OutputPath "preflight-$stamp"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("# Stamp preflight ($Mode)")
    [void]$md.AppendLine('')
    [void]$md.AppendLine("Run (UTC): $stamp  ")
    [void]$md.AppendLine("Script: Test-StampPreflight $ScriptVersion")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| Gate | Check | Status | Detail | Who must act |')
    [void]$md.AppendLine('|---|---|---|---|---|')
    foreach ($g in $Gates) { [void]$md.AppendLine("| $($g.Gate) | $($g.Check) | $($g.Status) | $($g.Detail) | $($g.'Who must act') |") }
    Set-Content -Path (Join-Path $dir 'preflight.md') -Value $md.ToString() -Encoding utf8
    @{ facts = $Facts; gates = $Gates } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $dir 'preflight.json') -Encoding utf8

    $manifest = Get-ChildItem $dir -File | ForEach-Object {
        [ordered]@{ file = $_.Name; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() }
    }
    @{ tool = "Test-StampPreflight $ScriptVersion"; mode = $Mode; files = @($manifest) } |
        ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dir 'MANIFEST.json') -Encoding utf8
    $dir
}

# ------------------------------------------------------------------ main
if ($FactsFile) {
    $facts = Get-Content -Raw -Path $FactsFile | ConvertFrom-Json
    $mode = 'offline'
} elseif ($SubscriptionId) {
    $facts = Get-LiveFact -SubscriptionId $SubscriptionId -Location $Location -VmSize $VmSize -RequiredProviders $RequiredProviders
    $mode = 'live'
} else {
    throw 'Pass -SubscriptionId (live) or -FactsFile (offline).'
}

$gates = Get-GateResult -Facts $facts -CoresNeeded $CoresNeeded -VmSize $VmSize
$gates | Format-Table -AutoSize | Out-String | Write-Host
$out = Write-PreflightEvidence -Gates $gates -Facts $facts -OutputPath $OutputPath -Mode $mode

$blocked = @($gates | Where-Object Status -eq 'BLOCKED').Count
Write-Host ("{0} gate(s) blocked. Evidence: {1}" -f $blocked, $out)
if ($FailOnBlocked -and $blocked -gt 0) { exit 1 }
