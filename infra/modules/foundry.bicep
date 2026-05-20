// =============================================================================
// foundry.bicep — Azure AI Foundry (AI Services kind=AIServices) with
// publicNetworkAccess DISABLED. Prompt agents are created in the Foundry portal.
// =============================================================================
@description('Region.')
param location string

@description('Foundry / AI Services account name.')
param accountName string

@description('Foundry project name.')
param projectName string

@description('SKU for the AI Services account.')
param sku string = 'S0'

@description('Model deployment name (referenced by the agent).')
param modelDeploymentName string = 'gpt-4o'

@description('Underlying model name to deploy.')
param modelName string = 'gpt-4o'

@description('Model version. Use a version GA in your region.')
param modelVersion string = '2024-11-20'

@description('Tokens-per-minute capacity (thousands). 10 = 10K TPM.')
param modelCapacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: { name: sku }
  identity: { type: 'SystemAssigned' }
  properties: {
    // Force callers to use AAD; disable shared keys entirely.
    disableLocalAuth: true
    // Required so we can create Foundry projects under this account.
    allowProjectManagement: true
    // The crown jewel — no public ingress to the AI endpoint.
    publicNetworkAccess: 'Disabled'
    customSubDomainName: accountName
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

// Foundry project (logical container for agents, datasets, evaluations, etc.)
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

// Model deployment — backing model for the weather-agent prompt agent.
// Created via the CONTROL plane (ARM), so it works even while the data plane
// endpoint is private.
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: modelDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

output accountId string         = account.id
output accountName string       = account.name
output endpoint string          = account.properties.endpoint
output projectId string         = project.id
output projectName string       = project.name
output modelDeploymentName string = modelDeployment.name
