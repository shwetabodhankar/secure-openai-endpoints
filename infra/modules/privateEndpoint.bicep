// =============================================================================
// privateEndpoint.bicep — Private Endpoint + DNS zone group for the Foundry account
// =============================================================================
@description('Region.')
param location string

@description('Workload short name.')
param workload string

@description('Foundry / AI Services account resource id.')
param foundryAccountId string

@description('Subnet id where the PE NIC will be attached.')
param subnetId string

@description('Private DNS zone ids to bind to the PE (openai, cognitiveservices, services.ai.azure.com).')
param privateDnsZoneIds array

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${workload}-foundry'
  location: location
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: 'foundry-plsc'
        properties: {
          privateLinkServiceId: foundryAccountId
          // 'account' is the correct groupId for Microsoft.CognitiveServices/accounts.
          groupIds: [ 'account' ]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in privateDnsZoneIds: {
      name: 'config-${i}'
      properties: { privateDnsZoneId: zoneId }
    }]
  }
}

output privateEndpointId string = pe.id
