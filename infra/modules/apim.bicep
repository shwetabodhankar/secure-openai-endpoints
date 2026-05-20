// =============================================================================
// apim.bicep — API Management in EXTERNAL VNet mode, with system-assigned MSI,
// the Bot Framework JWT validation policy, and the Foundry agent API.
// =============================================================================
@description('Region.')
param location string

@description('Workload short name.')
param workload string

@description('Suffix to keep the APIM name globally unique.')
param suffix string

@description('Resource id of the subnet APIM will be injected into.')
param apimSubnetId string

@description('Publisher email shown in the developer portal.')
param publisherEmail string

@description('Publisher name shown in the developer portal.')
param publisherName string

@description('App (client) ID of the Bot — used as the JWT audience claim.')
param botAppId string

@description('Secondary Bot App ID (Foundry auto-created bot) — additional valid JWT audience.')
param foundryBotAppId string = ''

@description('Entra ID tenant id.')
param tenantId string

@description('Backend Foundry endpoint, e.g. https://aoai-xxx.openai.azure.com')
param foundryEndpoint string

@description('SKU. Developer = non-prod, Premium = prod (only Premium supports VNet injection in production).')
@allowed([ 'Developer', 'Premium' ])
param skuName string = 'Developer'

@description('SKU capacity (units).')
param skuCapacity int = 1

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: 'apim-${workload}-${suffix}'
  location: location
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // EXTERNAL VNet mode: APIM is still reachable on a public IP (required so
    // the Bot Framework Channel Service can call us), but EGRESS to the backend
    // is routed through the VNet — i.e. through the Private Endpoint.
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
  }
}

// Global policy — apply Bot Framework JWT validation to every inbound call.
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../policies/apim-global-policy.xml')
  }
}

// Named value with the Bot's app id, referenced by the JWT audience check.
resource nvBotAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'bot-app-id'
  properties: {
    displayName: 'bot-app-id'
    value: botAppId
    secret: false
  }
}

// Named value with the secondary (Foundry-created) bot app id.
resource nvFoundryBotAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'foundry-bot-app-id'
  properties: {
    displayName: 'foundry-bot-app-id'
    value: empty(foundryBotAppId) ? botAppId : foundryBotAppId
    secret: false
  }
}

// Named value with the tenant id (handy if you later want issuer pinning per tenant).
resource nvTenantId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'tenant-id'
  properties: {
    displayName: 'tenant-id'
    value: tenantId
    secret: false
  }
}

// Backend pointing at the private Foundry endpoint. APIM will resolve this
// hostname through the linked Private DNS zone and hit the PE NIC.
resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'foundry-private'
  properties: {
    protocol: 'http'
    url: foundryEndpoint
    // NOTE: The bearer token is injected per-request in the API policy via
    // <authentication-managed-identity ... />, so no static credentials live here.
  }
}

// API surface exposed to the Bot Framework. The Bot's messaging endpoint will
// be https://<apim-host>/bot/api/messages — everything under /bot is policy-gated.
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'bot-agent'
  properties: {
    displayName: 'Bot → Foundry Agent'
    path: 'bot'
    protocols: [ 'https' ]
    subscriptionRequired: false  // Auth is enforced by validate-jwt, not subscription keys.
    serviceUrl: foundryEndpoint
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../policies/apim-agent-api-policy.xml')
  }
  dependsOn: [ backend, nvBotAppId, nvFoundryBotAppId ]
}

// A simple POST operation used as the Bot messaging endpoint.
resource opMessages 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'post-messages'
  properties: {
    displayName: 'POST /api/messages'
    method: 'POST'
    urlTemplate: '/api/messages'
  }
}

output apimHostname string = '${apim.name}.azure-api.net'
output principalId string  = apim.identity.principalId
