[CmdletBinding()]
param(
    [string] $ConfigurationPath = (Join-Path (Split-Path $PSScriptRoot) 'config/setup.json'),
    [switch] $Apply
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot
$config = Read-SetupConfiguration $ConfigurationPath
foreach ($tool in @('az', 'gh', 'dotnet', 'ssh-keygen', 'git')) { $null = Get-Command $tool -ErrorAction Stop }
$account = (Invoke-CheckedCommand az @('account', 'show', '--subscription', $config.subscriptionId, '--output', 'json')) -join "`n" | ConvertFrom-Json
if ($account.environmentName -ne 'AzureCloud') { throw 'v1 supports Azure public cloud and GitHub.com only.' }
$repo = Invoke-GithubApi "repos/$($config.repository)"
if (-not $repo.private -or -not $repo.permissions.admin -or $repo.default_branch -ne 'main') {
    throw 'Setup requires repository admin access to a PRIVATE adopter repository with default branch main.'
}
$remote = (Invoke-CheckedCommand git @('-C', $root, 'remote', 'get-url', 'origin')) -join ''
if ($remote -notin @("https://github.com/$($config.repository).git", "https://github.com/$($config.repository)", "git@github.com:$($config.repository).git")) {
    throw 'Configured repository must match this workspace origin. Do not run setup against the baseline.'
}
foreach ($workflow in @('database-ci.yml', 'promote-production.yml', 'verify-setup.yml')) {
    $null = Invoke-GithubApi "repos/$($config.repository)/contents/.github/workflows/${workflow}?ref=main"
}
$exists = (Invoke-CheckedCommand az @('group', 'exists', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName)) -join ''
if ($exists -eq 'true') {
    $group = (Invoke-CheckedCommand az @('group', 'show', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName, '--output', 'json')) -join "`n" | ConvertFrom-Json
    Assert-OwnedResourceGroup $group $config.repository
    if ($group.location -ne $config.location) { throw 'Existing resource group location differs; use its original configuration.' }
}
$stateDirectory = Join-Path $root '.azure'
$null = New-Item -ItemType Directory -Path $stateDirectory -Force
$statePath = Join-Path $stateDirectory 'setup-state.json'
if (Test-Path -LiteralPath $statePath) {
    $oldState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    foreach ($field in $config.PSObject.Properties.Name) {
        if ($oldState.configuration.$field -ne $config.$field) { throw "Changing '$field' on a rerun could replace resources. Use a separate checkout and NEW resource group." }
    }
}
$keyPath = Join-Path $stateDirectory 'runner_ed25519'
if (-not (Test-Path -LiteralPath "$keyPath.pub")) {
    if (Test-Path -LiteralPath $keyPath) { throw 'Runner private key exists without its public key. Restore the public key instead of replacing the private key.' }
    $null = Invoke-CheckedCommand ssh-keygen @('-t', 'ed25519', '-f', $keyPath, '-N', '', '-C', 'accelerator-runner')
}
$oidcSubjects = @{ dev = "repository_id:$($repo.id):environment:dev"; production = "repository_id:$($repo.id):environment:production" }
$parameters = @{
    location = $config.location; resourceGroupName = $config.resourceGroupName; resourcePrefix = $config.resourcePrefix
    repository = $config.repository; oidcSubjects = $oidcSubjects
    administratorObjectId = $config.administratorObjectId; administratorLogin = $config.administratorLogin
    administratorPrincipalType = $config.administratorPrincipalType
    sshPublicKey = (Get-Content -LiteralPath "$keyPath.pub" -Raw).Trim()
    runnerVmSize = $config.runnerVmSize; runnerAdminUsername = $config.runnerAdminUsername; vnetAddressPrefix = $config.vnetAddressPrefix
    runnerSubnetPrefix = $config.runnerSubnetPrefix; privateEndpointSubnetPrefix = $config.privateEndpointSubnetPrefix
}
$armParameters = @{}
foreach ($entry in $parameters.GetEnumerator()) { $armParameters[$entry.Key] = @{ value = $entry.Value } }
$parameterPath = Join-Path $stateDirectory 'parameters.json'
@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $armParameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterPath
$deploymentName = "sql-accelerator-$($config.resourcePrefix)-$($repo.id)"
$deploymentArguments = @('--subscription', $config.subscriptionId, '--location', $config.location, '--name', $deploymentName,
    '--template-file', (Join-Path $root 'infra/main.bicep'), '--parameters', "@$parameterPath")
Write-Host "Target: $($config.repository) / $($config.subscriptionId) / $($config.resourceGroupName)"
Write-Host 'Preview includes two SQL databases, a private runner VM, NAT gateway and private networking. Ongoing charges apply; see docs/COST-AND-CLEANUP.md.'
Invoke-CheckedCommand az (@('deployment', 'sub', 'what-if') + $deploymentArguments)
if (-not $Apply) { Write-Host 'Preview only. Review permissions and cost, then rerun with -Apply to provision and configure CI/CD.'; return }

@{ configuration = $config; complete = $false } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath
Set-GithubVariable $config.repository 'SETUP_COMPLETE' 'false'
Set-GithubVariable $config.repository 'SETUP_IN_PROGRESS' 'true'
$completed = $false
try {
    $environmentList = Invoke-GithubApi "repos/$($config.repository)/environments?per_page=100"
    foreach ($environmentName in @('dev', 'production')) {
        $existing = @($environmentList.environments | Where-Object name -eq $environmentName)
        if ($existing.Count -eq 0) {
            $null = Invoke-GithubApi "repos/$($config.repository)/environments/$environmentName" PUT @{
                deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
            }
            $null = Invoke-GithubApi "repos/$($config.repository)/environments/$environmentName/deployment-branch-policies" POST @{ name = 'main'; type = 'branch' }
        }
        else {
            $environment = Invoke-GithubApi "repos/$($config.repository)/environments/$environmentName"
            if (-not $environment.deployment_branch_policy -or -not $environment.deployment_branch_policy.custom_branch_policies) {
                throw "Existing environment '$environmentName' is not main-only. Configure custom branch policies before rerunning; setup will not weaken existing protections."
            }
            $policies = Invoke-GithubApi "repos/$($config.repository)/environments/$environmentName/deployment-branch-policies?per_page=100"
            if ($policies.branch_policies.Count -eq 0) {
                $null = Invoke-GithubApi "repos/$($config.repository)/environments/$environmentName/deployment-branch-policies" POST @{ name = 'main'; type = 'branch' }
            }
            elseif ($policies.branch_policies.Count -ne 1 -or $policies.branch_policies[0].name -ne 'main' -or $policies.branch_policies[0].type -ne 'branch') {
                throw "Environment '$environmentName' must allow only the main branch. Existing reviewers and wait timers are preserved."
            }
        }
        Set-GithubVariable $config.repository 'EXPECTED_OIDC_SUBJECT' $oidcSubjects[$environmentName] $environmentName
    }
    $oidc = Invoke-GithubApi "repos/$($config.repository)/actions/oidc/customization/sub"
    if (-not $oidc.use_default -and ($oidc.include_claim_keys -join ',') -ne 'repository_id,context') {
        throw 'Existing custom OIDC subject is incompatible. Review it explicitly before allowing setup to replace it.'
    }
    $null = Invoke-GithubApi "repos/$($config.repository)/actions/oidc/customization/sub" PUT @{
        use_default = $false; include_claim_keys = @('repository_id', 'context')
    }
    foreach ($provider in @('Microsoft.Sql', 'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.ManagedIdentity')) {
        $null = Invoke-CheckedCommand az @('provider', 'register', '--subscription', $config.subscriptionId, '--namespace', $provider, '--wait', '--output', 'none')
    }
    $null = Invoke-CheckedCommand az (@('deployment', 'sub', 'create') + $deploymentArguments + @('--output', 'none'))
    $configuration = (Invoke-CheckedCommand az @('deployment', 'sub', 'show', '--subscription', $config.subscriptionId,
        '--name', $deploymentName, '--query', 'properties.outputs.configuration.value', '--output', 'json')) -join "`n" | ConvertFrom-Json
    if (-not $configuration.serverFqdn -or $configuration.environments.Count -ne 2) { throw 'Deployment outputs are incomplete.' }
    $runnerName = "sql-$($repo.id)-$($config.resourcePrefix)"
    $runnerLabel = "sql-private-$($repo.id)"
    Set-GithubVariable $config.repository 'RUNNER_LABEL' $runnerLabel
    foreach ($target in $configuration.environments) {
        foreach ($entry in @{
            AZURE_CLIENT_ID = $target.clientId; AZURE_TENANT_ID = $configuration.tenantId
            AZURE_SUBSCRIPTION_ID = $configuration.subscriptionId; SQL_SERVER_FQDN = $configuration.serverFqdn
            SQL_DATABASE_NAME = $target.database; SQL_DEPLOYMENT_USER = $target.identityName
            SQL_PRIVATE_ENDPOINT_CIDR = $configuration.privateEndpointSubnetPrefix
        }.GetEnumerator()) { Set-GithubVariable $config.repository $entry.Key $entry.Value $target.name }
    }
    @{ configuration = $config; deployment = $configuration; repositoryId = $repo.id; runnerName = $runnerName; complete = $false } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath
    $null = Invoke-CheckedCommand az @('vm', 'start', '--subscription', $config.subscriptionId, '--resource-group', $configuration.resourceGroup, '--name', $configuration.runnerVm, '--output', 'none')
    $registration = Invoke-GithubApi "repos/$($config.repository)/actions/runners/registration-token" POST
    try {
        if (-not $registration.token) { throw 'Runner registration token was not returned.' }
        $runnerScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Initialize-PrivateRunner.sh') -Raw
        Invoke-PrivateRunCommand $configuration $runnerScript @("RunnerToken=$($registration.token)", "Repository=$($config.repository)",
            "RunnerName=$runnerName", "RunnerLabel=$runnerLabel", "SqlServerFqdn=$($configuration.serverFqdn)") 1800
    }
    finally { $registration = $null }
    $bootstrapScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Bootstrap-PrivateDatabases.ps1') -Raw)))
    $configurationBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($configuration | ConvertTo-Json -Depth 10 -Compress)))
    $shell = @"
#!/usr/bin/env bash
set -euo pipefail
file=`$(mktemp --suffix=.ps1)
trap 'rm -f "`$file"' EXIT
printf '%s' '$bootstrapScript' | base64 --decode > "`$file"
pwsh -NoProfile -File "`$file" -ConfigurationBase64 '$configurationBase64'
"@
    $token = (Invoke-CheckedCommand az @('account', 'get-access-token', '--subscription', $config.subscriptionId,
        '--resource', 'https://database.windows.net/', '--query', 'accessToken', '--output', 'tsv')) -join ''
    try {
        if (-not $token) { throw 'Could not obtain the setup administrator SQL access token.' }
        Invoke-PrivateRunCommand $configuration $shell @("SqlAccessToken=$token")
    }
    finally { $token = $null }
    $verification = Invoke-WorkflowAndWait $config.repository 'verify-setup.yml'
    Set-GithubVariable $config.repository 'SETUP_COMPLETE' 'true'
    $completed = $true
    @{ configuration = $config; deployment = $configuration; repositoryId = $repo.id; runnerName = $runnerName
        complete = $true; verificationUrl = $verification.html_url } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath
    Write-Host "Setup verified: $($verification.html_url). Dev deployments and production promotion are now enabled."
}
finally {
    Set-GithubVariable $config.repository 'SETUP_IN_PROGRESS' 'false'
    if (-not $completed) { Set-GithubVariable $config.repository 'SETUP_COMPLETE' 'false'; Write-Warning 'Setup is incomplete. Resources may exist and incur charges; fix the reported failure and rerun the same configuration.' }
}
