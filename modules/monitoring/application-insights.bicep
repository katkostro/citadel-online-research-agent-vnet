// Creates Application Insights and Log Analytics with network security features

@description('Azure region of the deployment')
param location string = resourceGroup().location

@description('Name of the Application Insights instance')
param applicationInsightsName string

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Tags to be applied to all resources')
param tags object = {}

@description('Name of the VNet')
param vnetName string

@description('VNet resource group name')
param vnetResourceGroupName string = resourceGroup().name

@description('VNet subscription ID')
param vnetSubscriptionId string = subscription().subscriptionId

@description('Subnet name for private endpoints')
param privateEndpointSubnetName string

@description('Suffix for unique resource names')
param suffix string

@description('Enable private endpoints for Application Insights (requires AllowPrivateEndpoints feature)')
param enablePrivateEndpoints bool = true

@description('Map of DNS zone FQDNs to resource group names. If provided, reference existing DNS zones.')
param existingDnsZones object = {
  'privatelink.monitor.azure.com': ''
  'privatelink.oms.opinsights.azure.com': ''
  'privatelink.ods.opinsights.azure.com': ''
  'privatelink.agentsvc.azure-automation.net': ''
}

// Create Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// Create Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// Reference existing network resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

// Private DNS zone names
var monitorDnsZoneName = 'privatelink.monitor.azure.com'
var omsDnsZoneName = 'privatelink.oms.opinsights.azure.com'
var odsDnsZoneName = 'privatelink.ods.opinsights.azure.com'
var agentServiceDnsZoneName = 'privatelink.agentsvc.azure-automation.net'

// DNS Zone Resource Group lookups
var monitorDnsZoneRG = existingDnsZones[monitorDnsZoneName]
var omsDnsZoneRG = existingDnsZones[omsDnsZoneName]
var odsDnsZoneRG = existingDnsZones[odsDnsZoneName]
var agentServiceDnsZoneRG = existingDnsZones[agentServiceDnsZoneName]

// Create or reference DNS zones
resource monitorPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(monitorDnsZoneRG)) {
  name: monitorDnsZoneName
  location: 'global'
}

resource existingMonitorPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(monitorDnsZoneRG)) {
  name: monitorDnsZoneName
  scope: resourceGroup(monitorDnsZoneRG)
}

resource omsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(omsDnsZoneRG)) {
  name: omsDnsZoneName
  location: 'global'
}

resource existingOmsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(omsDnsZoneRG)) {
  name: omsDnsZoneName
  scope: resourceGroup(omsDnsZoneRG)
}

resource odsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(odsDnsZoneRG)) {
  name: odsDnsZoneName
  location: 'global'
}

resource existingOdsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(odsDnsZoneRG)) {
  name: odsDnsZoneName
  scope: resourceGroup(odsDnsZoneRG)
}

resource agentServicePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(agentServiceDnsZoneRG)) {
  name: agentServiceDnsZoneName
  location: 'global'
}

resource existingAgentServicePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(agentServiceDnsZoneRG)) {
  name: agentServiceDnsZoneName
  scope: resourceGroup(agentServiceDnsZoneRG)
}

// DNS Zone IDs
var monitorDnsZoneId = empty(monitorDnsZoneRG) ? monitorPrivateDnsZone.id : existingMonitorPrivateDnsZone.id
var omsDnsZoneId = empty(omsDnsZoneRG) ? omsPrivateDnsZone.id : existingOmsPrivateDnsZone.id
var odsDnsZoneId = empty(odsDnsZoneRG) ? odsPrivateDnsZone.id : existingOdsPrivateDnsZone.id
var agentServiceDnsZoneId = empty(agentServiceDnsZoneRG) ? agentServicePrivateDnsZone.id : existingAgentServicePrivateDnsZone.id

// VNet links for DNS zones
resource monitorVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(monitorDnsZoneRG)) {
  parent: monitorPrivateDnsZone
  location: 'global'
  name: 'monitor-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource omsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(omsDnsZoneRG)) {
  parent: omsPrivateDnsZone
  location: 'global'
  name: 'oms-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource odsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(odsDnsZoneRG)) {
  parent: odsPrivateDnsZone
  location: 'global'
  name: 'ods-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource agentServiceVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(agentServiceDnsZoneRG)) {
  parent: agentServicePrivateDnsZone
  location: 'global'
  name: 'agentsvc-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// Private endpoints
resource applicationInsightsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (enablePrivateEndpoints) {
  name: '${applicationInsightsName}-private-endpoint'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${applicationInsightsName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: applicationInsights.id
          groupIds: ['azuremonitor']
        }
      }
    ]
  }
}

resource logAnalyticsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (enablePrivateEndpoints) {
  name: '${logAnalyticsWorkspaceName}-private-endpoint'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${logAnalyticsWorkspaceName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: logAnalyticsWorkspace.id
          groupIds: ['azuremonitor']
        }
      }
    ]
  }
}

// DNS zone groups
resource applicationInsightsDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (enablePrivateEndpoints) {
  parent: applicationInsightsPrivateEndpoint
  name: '${applicationInsightsName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: '${applicationInsightsName}-monitor-config'
        properties: {
          privateDnsZoneId: monitorDnsZoneId
        }
      }
    ]
  }
  dependsOn: [
    monitorVnetLink
  ]
}

resource logAnalyticsDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (enablePrivateEndpoints) {
  parent: logAnalyticsPrivateEndpoint
  name: '${logAnalyticsWorkspaceName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: '${logAnalyticsWorkspaceName}-oms-config'
        properties: {
          privateDnsZoneId: omsDnsZoneId
        }
      }
      {
        name: '${logAnalyticsWorkspaceName}-ods-config'
        properties: {
          privateDnsZoneId: odsDnsZoneId
        }
      }
      {
        name: '${logAnalyticsWorkspaceName}-agentsvc-config'
        properties: {
          privateDnsZoneId: agentServiceDnsZoneId
        }
      }
    ]
  }
  dependsOn: [
    omsVnetLink
    odsVnetLink
    agentServiceVnetLink
  ]
}

// Outputs
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
