// =============================================================================
// network.bicep — VNet, subnets, NSGs, Private DNS zones for Foundry/OpenAI
// =============================================================================
@description('Region.')
param location string

@description('Workload short name.')
param workload string

@description('VNet address space.')
param vnetAddressSpace string = '10.20.0.0/16'

@description('APIM subnet prefix (External VNet mode requires a dedicated subnet).')
param apimSubnetPrefix string = '10.20.1.0/24'

@description('Private Endpoint subnet prefix.')
param peSubnetPrefix string = '10.20.2.0/24'

@description('Azure Bastion subnet prefix. MUST be /26 or larger and named AzureBastionSubnet.')
param bastionSubnetPrefix string = '10.20.3.0/26'

@description('Jumpbox VM subnet prefix.')
param jumpSubnetPrefix string = '10.20.4.0/24'

// NSG for the APIM subnet — minimum required management ports are documented
// at https://learn.microsoft.com/azure/api-management/virtual-network-reference.
resource nsgApim 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${workload}-apim'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '6390'
        }
      }
      {
        name: 'Allow-Internet-Https-In'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// NSG for the Private Endpoint subnet — deny everything from the internet,
// only allow intra-VNet HTTPS (APIM → PE).
resource nsgPe 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${workload}-pe'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-VNet-Https-In'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Deny-Internet-In'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// NSG for the jumpbox subnet — only Bastion may RDP/SSH in.
resource nsgJump 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${workload}-jump'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Bastion-RDP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          // Bastion sources from the AzureBastionSubnet inside the VNet.
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [ '3389', '22' ]
        }
      }
      {
        name: 'Deny-Internet-In'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${workload}'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ vnetAddressSpace ] }
    subnets: [
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: { id: nsgApim.id }
          // APIM External VNet mode requires service endpoints for storage/sql/etc.
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
            { service: 'Microsoft.KeyVault' }
          ]
        }
      }
      {
        name: 'snet-pep'
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: { id: nsgPe.id }
          // Required so that the platform can create the NIC for the Private Endpoint.
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // MUST be named exactly 'AzureBastionSubnet'.
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: 'snet-jump'
        properties: {
          addressPrefix: jumpSubnetPrefix
          networkSecurityGroup: { id: nsgJump.id }
        }
      }
    ]
  }
}

// Private DNS zones — link them to the VNet so APIM can resolve the Foundry
// hostnames to the Private Endpoint IP.
var dnsZoneNames = [
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for z in dnsZoneNames: {
  name: z
  location: 'global'
}]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (z, i) in dnsZoneNames: {
  parent: zones[i]
  name: 'link-${workload}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}]

output vnetId string                     = vnet.id
output apimSubnetId string               = '${vnet.id}/subnets/snet-apim'
output peSubnetId string                 = '${vnet.id}/subnets/snet-pep'
output bastionSubnetId string            = '${vnet.id}/subnets/AzureBastionSubnet'
output jumpSubnetId string               = '${vnet.id}/subnets/snet-jump'
output openaiDnsZoneId string            = zones[0].id
output cognitiveServicesDnsZoneId string = zones[1].id
output aiServicesDnsZoneId string        = zones[2].id
