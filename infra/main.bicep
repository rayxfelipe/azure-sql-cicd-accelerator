targetScope = 'subscription'

@description('Azure region for all regional resources.')
param location string
@description('Dedicated accelerator-owned resource group. Setup refuses unrelated existing groups.')
param resourceGroupName string
@description('Lowercase alphanumeric resource prefix, 3-16 characters.')
@minLength(3)
@maxLength(16)
param resourcePrefix string
@description('GitHub owner/repository used for resource ownership tags.')
param repository string
@description('Actual environment-specific GitHub OIDC subjects, verified during setup.')
param oidcSubjects object
@description('Entra SQL administrator user or group object ID; not a deployment identity.')
param administratorObjectId string
@description('Entra SQL administrator display name.')
param administratorLogin string
@description('Entra administrator principal type.')
@allowed(['User', 'Group'])
param administratorPrincipalType string = 'User'
@description('SSH public key for the runner VM. No inbound SSH access is allowed.')
param sshPublicKey string
@description('Runner VM size; verify quota and regional availability before applying.')
param runnerVmSize string = 'Standard_B2s_v2'
@description('Linux administrator username for the runner VM, not its GitHub service account.')
param runnerAdminUsername string = 'runneradmin'
@description('Private VNet CIDR.')
param vnetAddressPrefix string = '10.90.0.0/16'
@description('Runner subnet CIDR, inside the VNet and separate from private endpoints.')
param runnerSubnetPrefix string = '10.90.1.0/24'
@description('Private endpoint subnet CIDR.')
param privateEndpointSubnetPrefix string = '10.90.2.0/24'

var tags = {
  'managed-by': 'azure-sql-cicd-accelerator'
  repository: repository
}
var serverName = 'sql-${resourcePrefix}-${uniqueString(subscription().id, resourceGroupName, repository)}'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module sql 'modules/sql.bicep' = {
  name: 'accelerator-sql'
  scope: rg
  params: {
    location: location
    serverName: serverName
    resourcePrefix: resourcePrefix
    oidcSubjects: oidcSubjects
    administratorObjectId: administratorObjectId
    administratorLogin: administratorLogin
    administratorPrincipalType: administratorPrincipalType
    tags: tags
  }
}

module runner 'modules/private-runner.bicep' = {
  name: 'accelerator-private-runner'
  scope: rg
  params: {
    location: location
    serverName: sql.outputs.configuration.serverName
    resourcePrefix: resourcePrefix
    sshPublicKey: sshPublicKey
    runnerVmSize: runnerVmSize
    adminUsername: runnerAdminUsername
    vnetAddressPrefix: vnetAddressPrefix
    runnerSubnetPrefix: runnerSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: tags
  }
}

output configuration object = union(sql.outputs.configuration, {
  location: location
  runnerVm: runner.outputs.runnerVm
  privateEndpoint: runner.outputs.privateEndpoint
  privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
})
