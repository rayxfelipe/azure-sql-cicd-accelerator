SET NOCOUNT ON;
IF DB_NAME() <> N'$(ExpectedDatabase)' OR USER_NAME() <> N'$(ExpectedUser)'
    THROW 51002, 'Readiness must run in the configured database as its deployment identity.', 1;
IF ISNULL(IS_ROLEMEMBER(N'db_owner'), 1) <> 0
    THROW 51003, 'Deployment identity must not be a db_owner member.', 1;
IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'CONNECT'), (N'VIEW DEFINITION'), (N'VIEW DATABASE STATE'),
        (N'CREATE TABLE'), (N'CREATE VIEW'), (N'CREATE PROCEDURE'), (N'CREATE FUNCTION'), (N'CREATE TYPE')
    ) AS required(PermissionName)
    WHERE ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', required.PermissionName), 0) <> 1
)
    THROW 51005, 'Required database deployment grants are missing.', 1;
IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'ALTER'), (N'SELECT'), (N'INSERT'), (N'UPDATE'), (N'DELETE'), (N'EXECUTE'), (N'REFERENCES')
    ) AS required(PermissionName)
    WHERE ISNULL(HAS_PERMS_BY_NAME(N'dbo', N'SCHEMA', required.PermissionName), 0) <> 1
)
    THROW 51006, 'Required dbo schema deployment grants are missing.', 1;
SELECT DB_NAME() AS DatabaseName, USER_NAME() AS DatabaseUser,
    N'PASS: private SQL connectivity, environment identity and deployment permissions' AS Readiness;
