[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ServerFqdn,
    [Parameter(Mandatory)][string] $Database,
    [Parameter(Mandatory)][string] $InputFile,
    [Parameter(Mandatory)][string] $ExpectedUser
)

. (Join-Path $PSScriptRoot 'Common.ps1')
foreach ($value in @($Database, $ExpectedUser)) {
    if ($value -notmatch '^[A-Za-z0-9_-]{1,128}$') { throw 'Database and expected identity must be valid accelerator SQL identifiers.' }
}
Import-Module SqlServer -RequiredVersion 22.4.5.1 -ErrorAction Stop
$token = (Invoke-CheckedCommand az @('account', 'get-access-token', '--resource', 'https://database.windows.net/', '--query', 'accessToken', '--output', 'tsv')) -join ''
try {
    if (-not $token) { throw 'Could not obtain an Entra SQL access token.' }
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Output "::add-mask::$token" }
    Invoke-Sqlcmd -ConnectionString "Server=tcp:$ServerFqdn,1433;Initial Catalog=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60" `
        -AccessToken $token -InputFile $InputFile -Variable @("ExpectedUser=$ExpectedUser", "ExpectedDatabase=$Database") `
        -QueryTimeout 180 -AbortOnError -OutputSqlErrors $true -ErrorAction Stop
}
finally { $token = $null }
