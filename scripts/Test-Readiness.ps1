[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ServerFqdn,
    [Parameter(Mandatory)][string] $Database,
    [Parameter(Mandatory)][string] $ExpectedUser,
    [Parameter(Mandatory)][string] $PrivateEndpointCidr
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-PrivateSqlConnection $ServerFqdn $PrivateEndpointCidr
& (Join-Path $PSScriptRoot 'Invoke-DatabaseSql.ps1') -ServerFqdn $ServerFqdn -Database $Database -ExpectedUser $ExpectedUser `
    -InputFile (Join-Path (Split-Path $PSScriptRoot) 'tests/Readiness.sql')
