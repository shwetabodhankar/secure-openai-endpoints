// =============================================================================
// rbac.bicep — Grant APIM's managed identity the "Azure AI User" role on the
// Foundry account, so APIM can call the agent endpoint with an AAD token.
// =============================================================================
@description('Existing Foundry / AI Services account name (parent scope).')
param foundryAccountName string

@description('Principal id of APIMs system-assigned managed identity.')
param principalId string

// Built-in role: "Azure AI User"
//   ID: 53ca6127-db72-4b80-b1b0-d745d6d5456d
//   This role grants data-plane access to Foundry projects, agents, and inference
//   without management-plane (control) permissions — i.e. least privilege.
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, principalId, azureAiUserRoleId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
  }
}
