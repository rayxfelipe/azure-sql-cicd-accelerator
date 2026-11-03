CREATE TABLE [dbo].[ServiceRequest]
(
    [ServiceRequestId] INT IDENTITY(1, 1) NOT NULL,
    [ReferenceCode] NVARCHAR(30) NOT NULL,
    [ServiceType] NVARCHAR(20) NOT NULL,
    [Status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_ServiceRequest_Status] DEFAULT N'Open',
    [CreatedAtUtc] DATETIME2(0) NOT NULL CONSTRAINT [DF_ServiceRequest_CreatedAtUtc] DEFAULT SYSUTCDATETIME(),
    [Priority] NVARCHAR(10) NOT NULL CONSTRAINT [DF_ServiceRequest_Priority] DEFAULT N'Normal',
    CONSTRAINT [PK_ServiceRequest] PRIMARY KEY ([ServiceRequestId]),
    CONSTRAINT [UQ_ServiceRequest_ReferenceCode] UNIQUE ([ReferenceCode]),
    CONSTRAINT [CK_ServiceRequest_ServiceType] CHECK ([ServiceType] IN (N'Water', N'Power')),
    CONSTRAINT [CK_ServiceRequest_Status] CHECK ([Status] IN (N'Open', N'In Progress', N'Closed'))
);
