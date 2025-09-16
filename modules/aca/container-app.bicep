// Container App module for hosting the API
@description('Location for all resources')
param location string

@description('Container App Environment name')
param containerAppEnvironmentName string

@description('Container App name')
param containerAppName string

@description('Container Registry login server (from early registry module)')
param containerRegistryLoginServer string
@description('Container Registry resource ID')
param containerRegistryId string

@description('AI Project endpoint URL')
param aiProjectEndpoint string

@description('ACA (Container Apps Environment infrastructure) subnet ID (distinct from agent and pe subnets)')
param acaSubnetId string

// peSubnetId no longer needed (registry private endpoint handled in separate module)
// Existing registry reference for role assignment scope
resource existingContainerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: last(split(containerRegistryId,'/'))
}

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

@description('Make the managed environment internal (provisions internal load balancer & private domain)')
param containerAppEnvironmentInternal bool = false

// Registry now provisioned separately; public network access handled there.

@description('Explicit internal Container Apps private DNS zone name (e.g. internal.<defaultDomain>). Provide after first deploy once defaultDomain known.')
param internalAcaDnsZoneName string = ''

@description('Create/link the internal ACA DNS zone (requires internalAcaDnsZoneName != empty)')
param internalAcaDnsZoneCreate bool = false

@description('Additional VNet resource IDs to link (APIM / hub VNets)')
param additionalInternalAcaDnsVnetIds array = []

@description('Mode for internal ACA DNS management: auto (deployment script discovers defaultDomain), explicit (use provided zone name), none (do nothing)')
@allowed(['auto','explicit','none'])
param internalAcaDnsMode string = 'auto'

@description('Master toggle to enable internal ACA DNS provisioning (zone + links + script). Keeps template valid when zone name empty by disabling all DNS resources.')
param internalAcaDnsEnabled bool = false

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

// Registry resources removed (handled in separate module)

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
      internal: containerAppEnvironmentInternal
    }
    zoneRedundant: false
  }
}

// Internal DNS zone creation only if explicitly requested and name supplied
// Backward compatibility: if internalAcaDnsMode not set by caller, internalAcaDnsZoneCreate drives behavior
// DNS logic must only engage when explicitly enabled AND the managed environment will be provisioned
var effectiveMode = internalAcaDnsMode != '' ? internalAcaDnsMode : (internalAcaDnsZoneCreate ? (empty(internalAcaDnsZoneName) ? 'auto' : 'explicit') : 'none')
var dnsFeatureEnabled = internalAcaDnsEnabled && createContainerApp && containerAppEnvironmentInternal
var useAuto = dnsFeatureEnabled && effectiveMode == 'auto'
var useExplicit = dnsFeatureEnabled && effectiveMode == 'explicit' && !empty(internalAcaDnsZoneName)

// Provide a safe placeholder to satisfy ARM template name validation when zone name is empty & feature disabled
var internalAcaDnsZoneNameEffective = !empty(internalAcaDnsZoneName) ? internalAcaDnsZoneName : 'skip-${substring(uniqueString(resourceGroup().id),0,6)}'

// Explicit zone creation
resource internalAcaDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (useExplicit && !empty(internalAcaDnsZoneName)) {
  name: internalAcaDnsZoneNameEffective
  location: 'global'
}

resource internalAcaDnsZoneVnetLinkPrimary 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (useExplicit && !empty(internalAcaDnsZoneName)) {
  parent: internalAcaDnsZone
  name: '${vnetName}-primary'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: '/subscriptions/${vnetSubscriptionId}/resourceGroups/${vnetResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${vnetName}'
    }
  }
}

resource internalAcaDnsZoneVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (vnetId, i) in additionalInternalAcaDnsVnetIds: if (useExplicit && !empty(internalAcaDnsZoneName)) {
  parent: internalAcaDnsZone
  name: 'extra-${i}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

// Automated creation via deployment script (auto mode)
resource internalAcaDnsDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (useAuto) {
  name: 'create-internal-aca-dns'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azCliVersion: '2.62.0'
    timeout: 'PT10M'
    retentionInterval: 'P1D'
    scriptContent: '''
set -euo pipefail
echo "Retrieving default domain..."
DEFAULT_DOMAIN=$(az resource show --ids ${CONTAINERAPPS_ENV_ID} --query properties.defaultDomain -o tsv)
ZONE_NAME="internal.${DEFAULT_DOMAIN}"
echo "Internal zone: $ZONE_NAME"
echo "Creating zone if not exists..."
az network private-dns zone create -g ${RESOURCE_GROUP} -n $ZONE_NAME --if-none-match >/dev/null

echo "Linking primary VNet..."
az network private-dns link vnet create -g ${RESOURCE_GROUP} -n primary-${RANDOM} -z $ZONE_NAME -v ${PRIMARY_VNET_ID} -e false --registration-enabled false >/dev/null || true

if [ -n "${ADDITIONAL_VNET_IDS}" ]; then
  echo "Processing additional VNets..."
  # ADDITIONAL_VNET_IDS is a comma-separated list
  IFS=',' read -ra VNARRAY <<< "${ADDITIONAL_VNET_IDS}"
  for VID in "${VNARRAY[@]}"; do
    if [ -n "$VID" ]; then
      LINK_NAME="extra-$(echo $VID | md5sum | cut -c1-8)"
      echo "Linking $VID as $LINK_NAME"
      az network private-dns link vnet create -g ${RESOURCE_GROUP} -n $LINK_NAME -z $ZONE_NAME -v $VID -e false --registration-enabled false >/dev/null || true
    fi
  done
fi

echo '{"zoneName":"'"$ZONE_NAME"'"}' > $AZ_SCRIPTS_OUTPUT_PATH
'''
    environmentVariables: [
      {
        name: 'CONTAINERAPPS_ENV_ID'
        value: containerAppEnvironment.id
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'PRIMARY_VNET_ID'
        value: '/subscriptions/${vnetSubscriptionId}/resourceGroups/${vnetResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${vnetName}'
      }
      {
        name: 'ADDITIONAL_VNET_IDS'
        value: length(additionalInternalAcaDnsVnetIds) > 0 ? join(additionalInternalAcaDnsVnetIds, ',') : ''
      }
    ]
  }
  // implicit dependency via reference to containerAppEnvironment.id in env vars
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
  // Updated to match application uvicorn listen port (was 50505 causing 404)
  targetPort: 8000
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
          server: containerRegistryLoginServer
          identity: containerAppUai.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          // Prefer digest if provided (immutability); otherwise fall back to tag.
          // Digest is injected via azd env set API_IMAGE_DIGEST <sha256> in predeploy hook.
          image: empty(containerImageDigest) ? '${containerRegistryLoginServer}/${containerName}:${containerImageTag}' : '${containerRegistryLoginServer}/${containerName}@sha256:${containerImageDigest}'
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
              // Align container PORT with ingress targetPort
              name: 'PORT'
              value: '8000'
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
  name: guid(containerRegistryId, containerAppUai.id, 'AcrPull')
  scope: existingContainerRegistry
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
output containerRegistryLoginServer string = containerRegistryLoginServer
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

// Additional outputs needed for main.bicep
output containerAppEnvironmentId string = containerAppEnvironment.id
output containerAppIdentityPrincipalId string = containerAppUai.properties.principalId
output containerAppIdentityClientId string = containerAppUai.properties.clientId
output containerAppIdentityId string = containerAppUai.id
// NOTE: Accessing containerApp.properties.configuration.ingress.fqdn can yield a null evaluation warning at compile time.
// We retain the deterministic constructed URI pattern for outputs; callers can query the resource after deployment for the exact FQDN.
output containerAppUri string = createContainerApp ? 'https://${containerApp.name}.gray.${location}.azurecontainerapps.io' : ''
// Output only for explicit mode (auto mode value must be queried post-deployment)
output internalAcaDnsZoneName string = useExplicit ? internalAcaDnsZoneNameEffective : ''
// Guard against null reference during what-if/compile (resource may not yet exist)
// In ARM/Bicep we cannot safely dereference ingress.fqdn at compile or early runtime without potential null; emit empty and let callers query post-deployment.
output internalAcaFqdn string = ''
