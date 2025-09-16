@description('Azure region')
param location string
@description('Container Registry name')
param containerRegistryName string
@description('Private Endpoint subnet ID')
param peSubnetId string
@description('VNet name for DNS linking')
param vnetName string
@description('VNet resource group name')
param vnetResourceGroupName string
@description('VNet subscription ID')
param vnetSubscriptionId string
@description('Public network access (Enabled for bootstrap builds, Disabled for fully private)')
@allowed(['Enabled','Disabled'])
param publicNetworkAccess string = 'Enabled'
@description('Tags')
param tags object = {}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: { name: 'Premium' }
  tags: tags
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: publicNetworkAccess
    networkRuleSet: {
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : 'Allow'
    }
  }
}

resource containerRegistryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (publicNetworkAccess == 'Disabled') {
  name: '${containerRegistryName}-pe'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: '${containerRegistryName}-conn'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

resource containerRegistryPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (publicNetworkAccess == 'Disabled') {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

resource containerRegistryPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (publicNetworkAccess == 'Disabled') {
  parent: containerRegistryPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: '/subscriptions/${vnetSubscriptionId}/resourceGroups/${vnetResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${vnetName}'
    }
  }
}

resource containerRegistryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (publicNetworkAccess == 'Disabled') {
  parent: containerRegistryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: { privateDnsZoneId: containerRegistryPrivateDnsZone.id }
      }
    ]
  }
}

output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryId string = containerRegistry.id
