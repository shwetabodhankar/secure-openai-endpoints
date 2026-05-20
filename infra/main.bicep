// =============================================================================
// main.bicep — Top-level deployment for the Teams → Bot → APIM → Private Foundry
// reference architecture. Deploy at the resource group scope.
// =============================================================================
targetScope = 'resourceGroup'

@description('Short workload name, used to derive resource names.')
param workload string = 'teamsai'

@description('Deployment region.')
param location string = resourceGroup().location

@description('Random suffix to keep globally-unique names unique.')
param suffix string = uniqueString(resourceGroup().id)

@description('Entra ID tenant id that owns the Bot app registration.')
param tenantId string = subscription().tenantId

@description('App (client) ID of the Entra ID app registration backing the Bot. Must be SINGLE TENANT.')
param botAppId string

@description('App ID of the secondary bot auto-created by Foundry "Publish to Teams" (used as additional valid JWT audience).')
param foundryBotAppId string = ''

@description('Publisher email for APIM.')
param apimPublisherEmail string

@description('Publisher name for APIM.')
param apimPublisherName string = 'Platform Team'

@description('Foundry / AI Services account name (must be globally unique).')
param foundryAccountName string = 'aoai-${workload}-${suffix}'

@description('Foundry project name (logical sub-resource within the account).')
param foundryProjectName string = 'sbodhankar-aveva-demo'

@description('Admin username for the jumpbox VM.')
param jumpAdminUsername string = 'azureadmin'

@secure()
@description('Admin password for the jumpbox VM. 12+ chars, complexity required.')
param jumpAdminPassword string

// -----------------------------------------------------------------------------
// 1. Network — VNet, subnets, NSGs, Private DNS zones
// -----------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    workload: workload
  }
}

// -----------------------------------------------------------------------------
// 2. Azure AI Foundry (AI Services) — public network access DISABLED
// -----------------------------------------------------------------------------
module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    accountName: foundryAccountName
    projectName: foundryProjectName
  }
}

// -----------------------------------------------------------------------------
// 3. Private Endpoint for Foundry + DNS zone group binding
// -----------------------------------------------------------------------------
module pe 'modules/privateEndpoint.bicep' = {
  name: 'foundry-pe'
  params: {
    location: location
    workload: workload
    foundryAccountId: foundry.outputs.accountId
    subnetId: network.outputs.peSubnetId
    privateDnsZoneIds: [
      network.outputs.openaiDnsZoneId
      network.outputs.cognitiveServicesDnsZoneId
      network.outputs.aiServicesDnsZoneId
    ]
  }
}

// -----------------------------------------------------------------------------
// 4. API Management — External VNet mode, system-assigned MSI
// -----------------------------------------------------------------------------
module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    location: location
    workload: workload
    suffix: suffix
    apimSubnetId: network.outputs.apimSubnetId
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    botAppId: botAppId
    foundryBotAppId: foundryBotAppId
    tenantId: tenantId
    foundryEndpoint: foundry.outputs.endpoint
  }
}

// -----------------------------------------------------------------------------
// 5. Azure Bot Service — single tenant, points at APIM
// -----------------------------------------------------------------------------
module bot 'modules/bot.bicep' = {
  name: 'bot'
  params: {
    location: 'global'
    workload: workload
    suffix: suffix
    tenantId: tenantId
    botAppId: botAppId
    // Bot messaging endpoint hits APIM, never the AI service directly.
    messagingEndpoint: 'https://${apim.outputs.apimHostname}/bot/api/messages'
  }
}

// -----------------------------------------------------------------------------
// 6. RBAC — grant APIM's MSI the Azure AI User role on the Foundry account
// -----------------------------------------------------------------------------
module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    foundryAccountName: foundry.outputs.accountName
    principalId: apim.outputs.principalId
  }
}

// -----------------------------------------------------------------------------
// 7. Jumpbox + Bastion — VNet-resident workstation for running data-plane scripts
// -----------------------------------------------------------------------------
module jump 'modules/jumpbox.bicep' = {
  name: 'jumpbox'
  params: {
    location:        location
    workload:        workload
    suffix:          suffix
    bastionSubnetId: network.outputs.bastionSubnetId
    jumpSubnetId:    network.outputs.jumpSubnetId
    adminUsername:   jumpAdminUsername
    adminPassword:   jumpAdminPassword
  }
}

// Grant the jumpbox VM's MSI the same Azure AI User role so create-weather-agent.ps1
// can authenticate without storing keys on the box.
module rbacJump 'modules/rbac.bicep' = {
  name: 'rbac-jump'
  params: {
    foundryAccountName: foundry.outputs.accountName
    principalId:        jump.outputs.vmPrincipalId
  }
}

output apimGatewayUrl string = 'https://${apim.outputs.apimHostname}'
output botMessagingEndpoint string = 'https://${apim.outputs.apimHostname}/bot/api/messages'
output foundryPrivateEndpointId string = pe.outputs.privateEndpointId
output jumpboxVmName string = jump.outputs.vmName
output bastionName string   = jump.outputs.bastionName
