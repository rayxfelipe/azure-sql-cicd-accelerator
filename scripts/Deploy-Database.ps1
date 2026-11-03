[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ServerFqdn,
    [Parameter(Mandatory)][string] $Database,
    [Parameter(Mandatory)][string] $ExpectedUser,
    [Parameter(Mandatory)][string] $PrivateEndpointCidr,
    [Parameter(Mandatory)][string] $Dacpac,
    [Parameter(Mandatory)][string] $SqlPackage,
    [string] $SmokeTest = (Join-Path (Split-Path $PSScriptRoot) 'tests/Smoke.sql')
)

. (Join-Path $PSScriptRoot 'Common.ps1')
foreach ($file in @($Dacpac, $SqlPackage, $SmokeTest)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required deployment file is missing: $file" }
}
if ($Database -notmatch '^[A-Za-z0-9_-]{1,128}$' -or $ExpectedUser -notmatch '^[A-Za-z0-9_-]{1,128}$') {
    throw 'Database and expected identity must be valid accelerator SQL identifiers.'
}
Assert-PrivateSqlConnection $ServerFqdn $PrivateEndpointCidr
$token = (Invoke-CheckedCommand az @('account', 'get-access-token', '--resource', 'https://database.windows.net/', '--query', 'accessToken', '--output', 'tsv')) -join ''
try {
    if (-not $token) { throw 'Could not obtain an Entra SQL access token.' }
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Output "::add-mask::$token" }
    $arguments = @(
        '/Action:Publish'
        "/SourceFile:$Dacpac"
        "/TargetConnectionString:Server=tcp:$ServerFqdn,1433;Initial Catalog=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60"
        "/AccessToken:$token"
        '/p:BlockOnPossibleDataLoss=True'
        '/p:DropObjectsNotInSource=False'
        '/p:ScriptDatabaseOptions=False'
        '/p:IgnorePermissions=True'
        '/p:IgnoreRoleMembership=True'
        '/p:ExcludeObjectTypes=Users;Logins;Permissions;RoleMembership'
    )
    Invoke-CheckedCommand $SqlPackage $arguments
    & (Join-Path $PSScriptRoot 'Invoke-DatabaseSql.ps1') -ServerFqdn $ServerFqdn -Database $Database -InputFile $SmokeTest -ExpectedUser $ExpectedUser
}
finally { $token = $null }
