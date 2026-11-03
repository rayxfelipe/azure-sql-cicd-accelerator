SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'$(ExpectedDatabase)' OR USER_NAME() <> N'$(ExpectedUser)'
    THROW 51002, 'Smoke test must run in the configured database as its deployment identity.', 1;
IF ISNULL(IS_ROLEMEMBER(N'db_owner'), 1) <> 0
    THROW 51003, 'Deployment identity must not be a db_owner member.', 1;
IF OBJECT_ID(N'dbo.ServiceRequest', N'U') IS NULL
    THROW 51000, 'ServiceRequest table is missing.', 1;
IF OBJECT_ID(N'dbo.ServiceRequestSummary', N'V') IS NULL
    THROW 51000, 'ServiceRequestSummary view is missing.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Reference NVARCHAR(30) = N'SMOKE-' + LEFT(CONVERT(NVARCHAR(36), NEWID()), 24);
    INSERT dbo.ServiceRequest (ReferenceCode, ServiceType, Status)
    VALUES (@Reference, N'Water', N'Open');
    IF NOT EXISTS (SELECT 1 FROM dbo.ServiceRequest WHERE ReferenceCode = @Reference AND Priority = N'Normal')
        THROW 51004, 'Priority column did not apply its expected default.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.ServiceRequestSummary
        WHERE ServiceType = N'Water' AND Status = N'Open' AND RequestCount > 0
    )
        THROW 51001, 'Summary view did not return the synthetic test request.', 1;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.ServiceRequest WHERE ReferenceCode = @Reference)
        THROW 51007, 'Synthetic smoke-test data was not rolled back.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
SELECT DB_NAME() AS DatabaseName, USER_NAME() AS DatabaseUser,
    N'PASS: environment identity, least-privilege role, Priority default, insert, query and rollback' AS SmokeTest;
