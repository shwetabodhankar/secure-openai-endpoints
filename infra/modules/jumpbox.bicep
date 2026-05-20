// =============================================================================
// jumpbox.bicep — Azure Bastion (Standard) + Windows Server 2022 jumpbox VM.
// Used as a VNet-resident workstation for running data-plane scripts (e.g.
// scripts/create-weather-agent.ps1) against the private Foundry endpoint.
// No public IP on the VM; access is RDP-over-Bastion only.
// =============================================================================
@description('Region.')
param location string

@description('Workload short name.')
param workload string

@description('Suffix for global-uniqueness.')
param suffix string

@description('Bastion subnet resource id (must be AzureBastionSubnet).')
param bastionSubnetId string

@description('Jumpbox subnet resource id.')
param jumpSubnetId string

@description('VM admin username.')
param adminUsername string = 'azureadmin'

@secure()
@description('VM admin password. 12+ chars, complexity required.')
param adminPassword string

@description('VM size. eastus2 capacity-checked: Standard_DC2s_v3 is currently the smallest commonly-available SKU in this subscription.')
param vmSize string = 'Standard_DC2s_v3'

// -----------------------------------------------------------------------------
// Bastion — public IP + Standard SKU host
// -----------------------------------------------------------------------------
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-bastion-${workload}-${suffix}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'bas-${workload}-${suffix}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet:          { id: bastionSubnetId }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
    // Standard SKU enables native client + tunneling if you ever need az ssh.
    enableTunneling: true
  }
}

// -----------------------------------------------------------------------------
// Jumpbox VM — Windows Server 2022, NO public IP
// -----------------------------------------------------------------------------
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-jump-${workload}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet:                    { id: jumpSubnetId }
          privateIPAllocationMethod: 'Dynamic'
          // Explicitly NO publicIPAddress — Zero Trust ingress via Bastion only.
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-jump-${workload}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName:  'vm-jump'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent:       true
        patchSettings:          { patchMode: 'AutomaticByPlatform' }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer:     'WindowsServer'
        sku:       '2022-datacenter-azure-edition'
        version:   'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'Premium_LRS' }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled:       true
      }
    }
  }
}

// Install Azure CLI on first boot so the user can immediately run the agent script.
resource cliInstall 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'install-azcli'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile $env:TEMP\\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList \'/I\', ($env:TEMP + \'\\AzureCLI.msi\'), \'/quiet\'"'
    }
  }
}

output bastionName string = bastion.name
output vmName string      = vm.name
output vmPrincipalId string = vm.identity.principalId
