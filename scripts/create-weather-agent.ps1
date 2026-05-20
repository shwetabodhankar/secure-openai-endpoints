<#
.SYNOPSIS
  Create the `weather-agent` prompt agent inside the Foundry project via the
  Agents data-plane API (Azure AI Agents service).

.DESCRIPTION
  Prompt agents are NOT ARM resources — they live on the data plane, so they
  can't be created from Bicep directly. This script:
    1. Acquires an AAD token for https://ai.azure.com/ (the Foundry data plane).
    2. POSTs an agent definition to the project's /assistants endpoint.

  The Foundry account in this template has publicNetworkAccess = Disabled, so
  the script must run from somewhere that can resolve and reach the Private
  Endpoint. Pick ONE:

    A) Run from a jumpbox VM joined to the VNet (recommended for production).
    B) Run from Azure Cloud Shell with VNet integration.
    C) For a quick demo: temporarily flip publicNetworkAccess to Enabled,
       run the script, then flip back. Pattern shown at the bottom.

.PARAMETER ResourceGroup
.PARAMETER AccountName
.PARAMETER ProjectName
.PARAMETER AgentName
.PARAMETER ModelDeploymentName
.PARAMETER Instructions
#>
param(
  [string]$ResourceGroup       = 'rg-teams-ai-secure',
  [string]$AccountName         = 'aoai-teamsai-6f3kmfw4v4zri',  # adjust to match deployment output
  [string]$ProjectName         = 'sbodhankar-aveva-demo',
  [string]$AgentName           = 'weather-agent',
  [string]$ModelDeploymentName = 'gpt-4o',
  [string]$Instructions        = @'
You are Weather Agent, a concise and friendly assistant that helps users with
weather information for any city worldwide.

Behaviour rules:
- If the user asks about weather, respond with current conditions, today's
  high/low, and a one-line outlook for the next 24 hours.
- If you do not have access to a live weather tool, state clearly that you
  are providing typical/seasonal expectations rather than a live reading.
- Keep responses under 80 words unless the user explicitly asks for detail.
- Refuse politely if asked about anything unrelated to weather, travel
  planning around weather, or what to wear/pack for a given forecast.
'@
)

$ErrorActionPreference = 'Stop'

Write-Host "Resolving Foundry account endpoint..." -ForegroundColor Cyan
$account = az cognitiveservices account show -g $ResourceGroup -n $AccountName -o json | ConvertFrom-Json
$endpoint = $account.properties.endpoint.TrimEnd('/')
Write-Host "Endpoint: $endpoint"

# Project-scoped data-plane base URL.
# Format: https://<account>.services.ai.azure.com/api/projects/<project>
$projectBase = "$endpoint/api/projects/$ProjectName"

Write-Host "Acquiring AAD token for Foundry data plane..." -ForegroundColor Cyan
$token = az account get-access-token --resource 'https://ai.azure.com/' --query accessToken -o tsv
if (-not $token) { throw 'Failed to acquire AAD token. Run `az login` first.' }

$headers = @{
  Authorization = "Bearer $token"
  'Content-Type' = 'application/json'
}

$body = @{
  name         = $AgentName
  model        = $ModelDeploymentName
  instructions = $Instructions
  tools        = @()
  metadata     = @{ source = 'bicep-post-deploy'; tenant = 'aveva-demo' }
} | ConvertTo-Json -Depth 8

# Agents API path (preview). The api-version may need a bump as Foundry GA's.
$uri = "$projectBase/assistants?api-version=2024-12-01-preview"

Write-Host "POST $uri" -ForegroundColor Cyan
try {
  $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
  Write-Host "Agent created:" -ForegroundColor Green
  $resp | ConvertTo-Json -Depth 6
} catch {
  Write-Error $_
  Write-Host "If this failed with 'cannot resolve host' or a timeout, you are not on the VNet." -ForegroundColor Yellow
  Write-Host "Quick-demo workaround (NOT for production):" -ForegroundColor Yellow
  Write-Host "  az cognitiveservices account update -g $ResourceGroup -n $AccountName --custom-domain $AccountName --api-properties publicNetworkAccess=Enabled" -ForegroundColor Yellow
  Write-Host "  # re-run this script" -ForegroundColor Yellow
  Write-Host "  az cognitiveservices account update -g $ResourceGroup -n $AccountName --api-properties publicNetworkAccess=Disabled" -ForegroundColor Yellow
}
