[CmdletBinding()]
param(
    [string] $ConfigurationPath = (Join-Path (Split-Path $PSScriptRoot) 'config/setup.json'),
    [switch] $Apply
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-SetupConfiguration $ConfigurationPath
$exists = (Invoke-CheckedCommand az @('group', 'exists', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName)) -join ''
if ($exists -eq 'true') {
    $group = (Invoke-CheckedCommand az @('group', 'show', '--subscription', $config.subscriptionId, '--name', $config.resourceGroupName, '--output', 'json')) -join "`n" | ConvertFrom-Json
    Assert-OwnedResourceGroup $group $config.repository
    Invoke-CheckedCommand az @('resource', 'list', '--subscription', $config.subscriptionId, '--resource-group', $config.resourceGroupName, '--output', 'table')
}
else { Write-Host 'Azure resource group is already absent. -Apply can finish a previously recorded runner cleanup.' }
if (-not $Apply) { Write-Host 'Preview only. -Apply permanently deletes this accelerator resource group and ALL its data, then removes its recorded runner registrations. Export required data first.'; return }
$statePath = Join-Path (Split-Path $PSScriptRoot) '.azure/setup-state.json'
Remove-AcceleratorResources -Configuration $config -StatePath $statePath -ResourceGroupExists ($exists -eq 'true')
