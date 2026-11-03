[CmdletBinding()]
param(
    [string] $ConfigurationPath = (Join-Path (Split-Path $PSScriptRoot) 'config/setup.json'),
    [switch] $Apply
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-SetupConfiguration $ConfigurationPath
$exists = (Invoke-CheckedCommand az @('group', 'exists', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName)) -join ''
if ($exists -ne 'true') { Write-Host 'Resource group is already absent. GitHub settings are unchanged.'; return }
$group = (Invoke-CheckedCommand az @('group', 'show', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName, '--output', 'json')) -join "`n" | ConvertFrom-Json
Assert-OwnedResourceGroup $group $config.repository
Invoke-CheckedCommand az @('resource', 'list', '--subscription', $config.subscriptionId, '--resource-group', $config.resourceGroupName, '--output', 'table')
if (-not $Apply) { Write-Host 'Preview only. -Apply permanently deletes this accelerator resource group and ALL its data. Export required data first.'; return }
Set-GithubVariable $config.repository 'SETUP_COMPLETE' 'false'
Set-GithubVariable $config.repository 'SETUP_IN_PROGRESS' 'false'
Assert-NoActiveReleaseRuns $config.repository
$repo = Invoke-GithubApi "repos/$($config.repository)"
$runnerName = "sql-$($repo.id)-$($config.resourcePrefix)"
$runners = Invoke-GithubApi "repos/$($config.repository)/actions/runners?per_page=100"
if ($runners.total_count -gt 100) { throw 'Refusing cleanup with a truncated runner list.' }
foreach ($runner in @($runners.runners | Where-Object name -eq $runnerName)) {
    if ($runner.busy) { throw 'Accelerator runner is busy. Wait for or cancel its workflow before cleanup.' }
    $null = Invoke-GithubApi "repos/$($config.repository)/actions/runners/$($runner.id)" DELETE
}
$null = Invoke-CheckedCommand az @('group', 'delete', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName, '--yes')
$remaining = (Invoke-CheckedCommand az @('group', 'exists', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName)) -join ''
if ($remaining -ne 'false') { throw 'Resource group deletion has not completed.' }
Write-Host 'Accelerator Azure resources deleted; GitHub deployments disabled. Repository, environments and OIDC subject customization were retained.'
