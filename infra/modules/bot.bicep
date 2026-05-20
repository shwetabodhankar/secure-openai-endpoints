// =============================================================================
// bot.bicep — Azure Bot Service registration, SINGLE-TENANT.
// The bot's messaging endpoint is APIM (never the AI service directly).
// =============================================================================
@description('Bot Service is a global resource.')
param location string = 'global'

@description('Workload short name.')
param workload string

@description('Suffix to keep the name unique.')
param suffix string

@description('Entra ID tenant id (single-tenant bot).')
param tenantId string

@description('App (client) ID of the Entra ID app registration backing the Bot.')
param botAppId string

@description('Messaging endpoint — must be the APIM URL, not the AI service.')
param messagingEndpoint string

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: 'bot-${workload}-${suffix}'
  location: location
  kind: 'azurebot'
  sku: { name: 'S1' }
  properties: {
    displayName: 'Travel Agent (Teams)'
    endpoint: messagingEndpoint
    msaAppId: botAppId
    // SINGLE TENANT — narrows the trust boundary to this Entra ID tenant only.
    msaAppType: 'SingleTenant'
    msaAppTenantId: tenantId
    publicNetworkAccess: 'Enabled' // Bot Connector is a SaaS; this controls Direct Line / channels only.
    disableLocalAuth: false
  }
}

// Enable the Microsoft Teams channel.
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

output botName string = bot.name
output botId string   = bot.id
