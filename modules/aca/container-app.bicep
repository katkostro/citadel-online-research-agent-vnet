// Container App module for hosting the API
@description('Location for all resources')
param location string

@description('Container App Environment name')
param containerAppEnvironmentName string

@description('Container App name')
param containerAppName string

@description('Container Registry name')
param containerRegistryName string

@description('AI Project endpoint URL')
param aiProjectEndpoint string

@description('ACA (Container Apps Environment infrastructure) subnet ID (distinct from agent and pe subnets)')
param acaSubnetId string

@description('Private Endpoint subnet ID')
param peSubnetId string

@description('VNet name for private endpoint integration')
param vnetName string

@description('VNet resource group name')
param vnetResourceGroupName string

@description('VNet subscription ID')
param vnetSubscriptionId string

@description('Log Analytics Workspace resource ID from Application Insights module')
param logAnalyticsWorkspaceId string

@description('Application Insights connection string')
param applicationInsightsConnectionString string

@description('Application Insights instrumentation key')
param applicationInsightsInstrumentationKey string

@description('Enable Bing Search for web search capabilities')
param enableBingSearch bool = false

@description('Bing Search endpoint URL (optional)')
param bingSearchEndpoint string = ''

@description('Bing Search API key (optional)')
@secure()
param bingSearchApiKey string = ''

@description('Container App ingress type: external (internet-accessible) or internal (VNet-only)')
@allowed(['external', 'internal'])
param containerAppIngressType string = 'internal'

@description('Name of the AI agent application')
param agentName string = 'citadel-research-agent'

@description('Name of the container')
param containerName string = 'citadel-api'

@description('Image tag to deploy (ignored if containerImageDigest provided)')
param containerImageTag string = 'latest'

@description('Image digest value without the sha256: prefix (set via azd env if needed)')
param containerImageDigest string = ''

@description('Tags to be applied to all resources')
param tags object = {}

@description('Whether to create the Container App resource now (set false for two-phase deployment: infra first, image build, then app).')
param createContainerApp bool = true

// Reference to existing Log Analytics Workspace from Application Insights module
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
  scope: resourceGroup(split(logAnalyticsWorkspaceId, '/')[2], split(logAnalyticsWorkspaceId, '/')[4])
}

// Container Registry with (temporarily) public network access enabled so build/push works; will rely on private endpoint + DNS later
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Premium' // Premium required for private endpoints
  }
  properties: {
    adminUserEnabled: false // Enforce managed identity (no admin creds)
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      defaultAction: 'Allow'
    }
  }
}

// Private Endpoint for Container Registry
resource containerRegistryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${containerRegistryName}-private-endpoint'
  location: location
  properties: {
    subnet: {
      id: peSubnetId  // Put Container Registry private endpoint in pe-subnet
    }
    privateLinkServiceConnections: [
      {
        name: '${containerRegistryName}-private-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

// Private DNS Zone for Container Registry
resource containerRegistryPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

// Link private DNS zone to VNet
resource containerRegistryPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
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

// Private DNS Zone Group for Container Registry
resource containerRegistryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: containerRegistryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: containerRegistryPrivateDnsZone.id
        }
      }
    ]
  }
}

// Container App Environment with VNet integration and Log Analytics
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
    }
    zoneRedundant: false
  }
}

// User Assigned Managed Identity (breaks circular dependency for ACR pull)
resource containerAppUai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppName}-uai'
  location: location
}

// Container App (uses user-assigned managed identity for ACR)
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = if (createContainerApp) {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppUai.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: containerAppIngressType == 'external'
        targetPort: 50505
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppUai.id // user-assigned identity resource id
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          // Prefer digest if provided (immutability); otherwise fall back to tag.
          // Digest is injected via azd env set API_IMAGE_DIGEST <sha256> in predeploy hook.
          image: empty(containerImageDigest) ? '${containerRegistry.properties.loginServer}/${containerName}:${containerImageTag}' : '${containerRegistry.properties.loginServer}/${containerName}@sha256:${containerImageDigest}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: union([
            {
              name: 'AZURE_EXISTING_AIPROJECT_ENDPOINT'
              value: aiProjectEndpoint
            }
            {
              name: 'AZURE_AI_AGENT_NAME'
              value: agentName
            }
            {
              name: 'PORT'
              value: '50505'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: ''
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: applicationInsightsInstrumentationKey
            }
            {
              name: 'ENABLE_AZURE_MONITOR_TRACING'
              value: 'true'
            }
            {
              name: 'AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED'
              value: 'true'
            }
          ], enableBingSearch ? [
            {
              name: 'ENABLE_BING_SEARCH'
              value: 'true'
            }
            {
              name: 'BING_SEARCH_ENDPOINT'
              value: bingSearchEndpoint
            }
            {
              name: 'BING_SEARCH_API_KEY'
              value: bingSearchApiKey
            }
          ] : [])
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scale'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
  ]
}

// Role assignment granting ACR pull to the user-assigned identity (no circular dependency)
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createContainerApp) {
  name: guid(containerRegistry.id, containerAppUai.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerAppUai.properties.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
  ]
}

// Safe outputs (empty when container app not yet created)
// Placeholder FQDN pattern; actual FQDN retrieved once resource exists.
output containerAppName string = createContainerApp ? containerApp.name : containerAppName
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

// Additional outputs needed for main.bicep
output containerAppEnvironmentId string = containerAppEnvironment.id
output containerAppIdentityPrincipalId string = containerAppUai.properties.principalId
output containerAppIdentityClientId string = containerAppUai.properties.clientId
output containerAppIdentityId string = containerAppUai.id
// NOTE: Accessing containerApp.properties.configuration.ingress.fqdn can yield a null evaluation warning at compile time.
// We retain the deterministic constructed URI pattern for outputs; callers can query the resource after deployment for the exact FQDN.
output containerAppUri string = createContainerApp ? 'https://${containerApp.name}.gray.${location}.azurecontainerapps.io' : ''
