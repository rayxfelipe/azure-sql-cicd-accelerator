[CmdletBinding()]
param([Parameter(Mandatory)][string] $ConfigurationBase64)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $env:SqlAccessToken) { throw 'A protected SqlAccessToken parameter is required.' }
$configuration = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConfigurationBase64)) | ConvertFrom-Json
Import-Module SqlServer -RequiredVersion 22.4.5.1 -ErrorAction Stop
foreach ($target in $configuration.environments) {
    $sid = '0x' + [Convert]::ToHexString(([guid]$target.clientId).ToByteArray())
    $user = $target.identityName.Replace("'", "''")
    $identifier = $target.identityName.Replace(']', ']]')
    $query = @"
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$user' AND sid <> $sid)
    THROW 51010, 'Deployment user SID differs. Refusing to drop or replace an existing principal.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$user')
    CREATE USER [$identifier] WITH SID = $sid, TYPE = E;
GRANT CONNECT, VIEW DEFINITION, VIEW DATABASE STATE TO [$identifier];
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION, CREATE TYPE TO [$identifier];
GRANT ALTER, SELECT, INSERT, UPDATE, DELETE, EXECUTE, REFERENCES ON SCHEMA::dbo TO [$identifier];
SELECT DB_NAME() AS DatabaseName, name AS IdentityName, type_desc AS PrincipalType
FROM sys.database_principals WHERE name = N'$user';
"@
    if ($configuration.serverFqdn -notmatch '^[a-z0-9-]+\.database\.windows\.net$' -or $target.database -notmatch '^[A-Za-z0-9_-]{1,128}$') {
        throw 'Deployment output contains an invalid SQL hostname or database identifier.'
    }
    Invoke-Sqlcmd -ConnectionString "Server=tcp:$($configuration.serverFqdn),1433;Initial Catalog=$($target.database);Encrypt=True;TrustServerCertificate=False;Connection Timeout=60" -AccessToken $env:SqlAccessToken `
        -Query $query -QueryTimeout 180 -AbortOnError -OutputSqlErrors $true -ErrorAction Stop
}
