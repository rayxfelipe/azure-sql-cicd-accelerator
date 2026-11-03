CREATE VIEW [dbo].[ServiceRequestSummary]
AS
    SELECT [ServiceType], [Status], COUNT_BIG(*) AS [RequestCount]
    FROM [dbo].[ServiceRequest]
    GROUP BY [ServiceType], [Status];
