param location string
param serverName string
param resourcePrefix string
param oidcSubjects object
param administratorObjectId string
param administratorLogin string
param administratorPrincipalType string
param tags object

var environments = [
  { name: 'dev', database: 'sqldb-${resourcePrefix}-dev', identity: 'id-${resourcePrefix}-dev' }
  { name: 'production', database: 'sqldb-${resourcePrefix}-prod', identity: 'id-${resourcePrefix}-prod' }
]

resource identities 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = [for env in environments: {
  name: env.identity
  location: location
  tags: tags
}]

resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = [for (env, i) in environments: {
  parent: identities[i]
  name: 'github-${env.name}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: oidcSubjects[env.name]
    audiences: ['api://AzureADTokenExchange']
  }
}]

resource server 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: administratorPrincipalType
      login: administratorLogin
      sid: administratorObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

resource databases 'Microsoft.Sql/servers/databases@2023-08-01' = [for env in environments: {
  parent: server
  name: env.database
  location: location
  tags: tags
  sku: { name: 'Basic', tier: 'Basic', capacity: 5 }
  properties: {
    maxSizeBytes: 2147483648
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    requestedBackupStorageRedundancy: 'Local'
  }
}]

resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (env, i) in environments: {
  name: guid(resourceGroup().id, env.identity, 'reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: identities[i].properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

output configuration object = {
  serverName: server.name
  serverFqdn: server.properties.fullyQualifiedDomainName
  resourceGroup: resourceGroup().name
  tenantId: tenant().tenantId
  subscriptionId: subscription().subscriptionId
  environments: [
    {
      name: environments[0].name
      database: environments[0].database
      identityName: environments[0].identity
      clientId: identities[0].properties.clientId
      principalId: identities[0].properties.principalId
    }
    {
      name: environments[1].name
      database: environments[1].database
      identityName: environments[1].identity
      clientId: identities[1].properties.clientId
      principalId: identities[1].properties.principalId
    }
  ]
}
