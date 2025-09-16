/*
Standard Setup Network Secured Steps for main.bicep
-----------------------------------
This template is designed for IDEMPOTENT deployments:
- Resources are updated, not duplicated on repeat deployments
- Uses stable naming with uniqueString(resourceGroup().id)
- Azure Resource Manager handles incremental updates
- AZD maintains deployment state in .azure/ directory
*/
@description('Location for all resources.')
@allowed([
  'westus'
  'eastus'
  'eastus2'
  'japaneast'
  'francecentral'
  'spaincentral'
  'uaenorth'
  'southcentralus'
  'italynorth'
  'germanywestcentral'
  'brazilsouth'
  'southafricanorth'
  'australiaeast'
  'swedencentral'

  // allowed only Class B and C
  'westus3'
  'centralus'
  'uksouth'
  'southindia'
  'koreacentral'
  'polandcentral'
  'switzerlandnorth'
  'norwayeast'
])
param location string = 'eastus2'

@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('Tags to apply to all resources')
param tags object = {}

// Add AZD-required tags
var azdTags = union(tags, {
  'azd-env-name': environmentName
  'azd-service-name': 'api'
})

// Debug output
output debugTags object = azdTags
output debugInputTags object = tags
output debugEnvironmentName string = environmentName

// Model deployment parameters
@description('The name of the model you want to deploy')
param modelName string = 'gpt-4o'
@description('The provider of your model')
param modelFormat string = 'OpenAI'
@description('The version of your model')
param modelVersion string = '2024-11-20'
@description('The sku of your model deployment')
param modelSkuName string = 'GlobalStandard'
@description('The tokens per minute (TPM) of your model deployment')
param modelCapacity int = 30

@description('Optional stable 4-char suffix to override automatic unique hash for reproducible naming (e.g. reuse existing resources). Leave blank to auto-generate.')
@maxLength(4)
param stableSuffix string = ''

// Create a short, unique suffix, or use provided stable suffix
var computedSuffix = substring(uniqueString(subscription().id, resourceGroup().id, location, environmentName), 0, 4)
var uniqueSuffix = empty(stableSuffix) ? computedSuffix : toLower(stableSuffix)

// Service-specific naming for clarity
var aiAccountName = toLower('aifoundry-${uniqueSuffix}')
var storageAccountName = toLower('storage${uniqueSuffix}')
var cosmosAccountName = toLower('cosmos-${uniqueSuffix}')
var searchAccountName = toLower('aisearch-${uniqueSuffix}')
var bingSearchName = toLower('bing-${uniqueSuffix}')

@description('Name for your project resource.')
param firstProjectName string = 'project'

@description('This project will be a sub-resource of your account')
param projectDescription string = 'A project for the AI Foundry account with network secured deployed Agent'

@description('The display name of the project')
param displayName string = 'network secured agent project'

// Existing Virtual Network parameters
@description('Virtual Network name (auto-default for azd if not supplied)')
param vnetName string = toLower('vnet-${environmentName}')

@description('Agent subnet name (default)')
param agentSubnetName string = toLower('${environmentName}-agent-snet')

@description('ACA infrastructure subnet name (default)')
param acaSubnetName string = toLower('${environmentName}-aca-snet')

@description('Private Endpoint subnet name (default)')
param peSubnetName string = toLower('${environmentName}-pe-snet')

//Existing standard Agent required resources
@description('Existing Virtual Network name Resource ID')
param existingVnetResourceId string = ''

@description('Address space for the VNet (only used for new VNet)')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet.')
param agentSubnetPrefix string = ''

@description('Address prefix for the ACA infrastructure subnet')
param acaSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchResourceId string = ''
@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureStorageAccountResourceId string = ''
@description('The Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureCosmosDBAccountResourceId string = ''

@description('Enable Bing Search for web search capabilities')
param enableBingSearch bool = true

@description('Container App ingress type: external (internet-accessible) or internal (VNet-only)')
@allowed(['external', 'internal'])
param containerAppIngressType string = 'internal'

@description('Make the Container Apps managed environment internal-only (provisions internal load balancer)')
param containerAppEnvironmentInternal bool = true

@description('Create Private DNS zone for internal Container Apps domain and link primary VNet')
param createInternalAcaDnsZone bool = false

@description('Optional: Additional VNet resource IDs to link to the internal Container Apps private DNS zone (e.g., APIM VNet)')
param additionalInternalAcaDnsVnetIds array = []

@description('Mode for internal ACA DNS management: auto (discover defaultDomain & create zone), explicit (use provided internalAcaDnsZoneName), none (skip)')
@allowed(['auto','explicit','none'])
param internalAcaDnsMode string = 'auto'

@description('Master toggle to enable internal ACA DNS resources (private zone + links). Leave false until you want DNS immediately with the environment.')
param internalAcaDnsEnabled bool = false

@description('Create the Container App during infra provisioning (set false for two-phase deploy).')
param createContainerApp bool = true

@description('Enable private endpoints for Application Insights and Log Analytics (preview/feature dependent).')
param enableMonitoringPrivateEndpoints bool = true

@description('Optional: Resource ID of APIM VNet to peer with primary VNet (enables APIM access to internal Container App). Leave empty for none.')
param apimVnetResourceId string = ''

@description('Create primary->APIM VNet peering (local side).')
param createApimVnetPeering bool = true

@description('Also create remote (APIM->primary) peering using deployment script (requires permission on remote VNet).')
param createApimReversePeering bool = false


//New Param for resource group of Private DNS zones
//@description('Optional: Resource group containing existing private DNS zones. If specified, DNS zones will not be created.')
//param existingDnsZonesResourceGroup string = ''

@description('Object mapping DNS zone names to their resource group, or empty string to indicate creation (storage blob zone auto-added).')
param existingDnsZones object = {
  'privatelink.services.ai.azure.com': ''
  'privatelink.openai.azure.com': ''
  'privatelink.cognitiveservices.azure.com': ''
  'privatelink.search.windows.net': ''
  'privatelink.documents.azure.com': ''
  'privatelink.monitor.azure.com': ''
  'privatelink.oms.opinsights.azure.com': ''
  'privatelink.ods.opinsights.azure.com': ''
  'privatelink.agentsvc.azure-automation.net': ''
}

var storageBlobPrivateZone = 'privatelink.blob.${environment().suffixes.storage}'
var enrichedExistingDnsZones = union(existingDnsZones, {
  '${storageBlobPrivateZone}': ''
})

@description('Base list of private DNS zone names (storage blob zone auto-added).')
param dnsZoneNames array = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

// Compose full zone list (including blob) for validator module
var enrichedDnsZoneNames = concat(dnsZoneNames, [storageBlobPrivateZone])


var projectName = toLower('${firstProjectName}${uniqueSuffix}')
// Use the new service-specific names defined above
var cosmosDBName = cosmosAccountName
var aiSearchName = searchAccountName
var azureStorageName = storageAccountName
// Container-related naming (keep legacy pattern for container services)
var containerAppName = toLower('aca-${uniqueSuffix}')
var containerAppEnvironmentName = toLower('cae-${uniqueSuffix}')
var containerRegistryName = toLower('acr${uniqueSuffix}')

// Check if existing resources have been passed in
var storagePassedIn = azureStorageAccountResourceId != ''
var searchPassedIn = aiSearchResourceId != ''
var cosmosPassedIn = azureCosmosDBAccountResourceId != ''
var existingVnetPassedIn = existingVnetResourceId != ''


var acsParts = split(aiSearchResourceId, '/')
var aiSearchServiceSubscriptionId = searchPassedIn ? acsParts[2] : subscription().subscriptionId
var aiSearchServiceResourceGroupName = searchPassedIn ? acsParts[4] : resourceGroup().name

var cosmosParts = split(azureCosmosDBAccountResourceId, '/')
var cosmosDBSubscriptionId = cosmosPassedIn ? cosmosParts[2] : subscription().subscriptionId
var cosmosDBResourceGroupName = cosmosPassedIn ? cosmosParts[4] : resourceGroup().name

var storageParts = split(azureStorageAccountResourceId, '/')
var azureStorageSubscriptionId = storagePassedIn ? storageParts[2] : subscription().subscriptionId
var azureStorageResourceGroupName = storagePassedIn ? storageParts[4] : resourceGroup().name

var vnetParts = split(existingVnetResourceId, '/')
var vnetSubscriptionId = existingVnetPassedIn ? vnetParts[2] : subscription().subscriptionId
var vnetResourceGroupName = existingVnetPassedIn ? vnetParts[4] : resourceGroup().name
var existingVnetName = existingVnetPassedIn ? last(vnetParts) : vnetName
var trimVnetName = trim(existingVnetName)

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

// Create Virtual Network and Subnets
module vnet 'modules/networking/vnet-orchestrator.bicep' = {
  name: 'vnet-${trimVnetName}-${uniqueSuffix}-deployment'
  params: {
    location: location
    vnetName: trimVnetName
    useExistingVnet: existingVnetPassedIn
    existingVnetResourceGroupName: vnetResourceGroupName
    agentSubnetName: agentSubnetName
    acaSubnetName: acaSubnetName
    peSubnetName: peSubnetName
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    acaSubnetPrefix: acaSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
    existingVnetSubscriptionId: vnetSubscriptionId
  }
}

// Deploy Container Registry early so remote build can occur even if AI account later fails
module containerRegistry 'modules/aca/container-registry.bicep' = {
  name: 'acr-${containerRegistryName}-${uniqueSuffix}-deployment'
  params: {
    location: location
    containerRegistryName: containerRegistryName
    peSubnetId: vnet.outputs.peSubnetId
    vnetName: vnet.outputs.virtualNetworkName
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId
    publicNetworkAccess: 'Enabled'
    tags: azdTags
  }
}

/*  Create the AI Services account and gpt-4o model deployment */
module aiAccount 'modules/ai-services/ai-account.bicep' = {
  name: 'ai-${aiAccountName}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    accountName: aiAccountName
    location: location
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    agentSubnetId: vnet.outputs.agentSubnetId
  }
}
/*
  Validate existing resources
  This module will check if the AI Search Service, Storage Account, and Cosmos DB Account already exist.
  If they do, it will set the corresponding output to true. If they do not exist, it will set the output to false.
*/
module validateExistingResources 'modules/utilities/resource-validator.bicep' = {
  name: 'validate-existing-resources-${uniqueSuffix}-deployment'
  params: {
    aiSearchResourceId: aiSearchResourceId
    azureStorageAccountResourceId: azureStorageAccountResourceId
    azureCosmosDBAccountResourceId: azureCosmosDBAccountResourceId
  existingDnsZones: enrichedExistingDnsZones
  dnsZoneNames: enrichedDnsZoneNames
  }
}

// This module will create new agent dependent resources
// A Cosmos DB account, an AI Search Service, and a Storage Account are created if they do not already exist
module aiDependencies 'modules/utilities/standard-dependent-resources.bicep' = {
  name: 'dependencies-${aiAccountName}-${uniqueSuffix}-deployment'
  params: {
    location: location
    azureStorageName: azureStorageName
    aiSearchName: aiSearchName
    cosmosDBName: cosmosDBName

    // AI Search Service parameters
    aiSearchResourceId: aiSearchResourceId
    aiSearchExists: validateExistingResources.outputs.aiSearchExists

    // Storage Account
    azureStorageAccountResourceId: azureStorageAccountResourceId
    azureStorageExists: validateExistingResources.outputs.azureStorageExists

    // Cosmos DB Account
    cosmosDBResourceId: azureCosmosDBAccountResourceId
    cosmosDBExists: validateExistingResources.outputs.cosmosDBExists
    }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: aiDependencies.outputs.azureStorageName
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
}


resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiDependencies.outputs.aiSearchName
  scope: resourceGroup(aiDependencies.outputs.aiSearchServiceSubscriptionId, aiDependencies.outputs.aiSearchServiceResourceGroupName)
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: aiDependencies.outputs.cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}

// Private Endpoint and DNS Configuration
// This module sets up private network access for all Azure services:
// 1. Creates private endpoints in the specified subnet
// 2. Sets up private DNS zones for each service
// 3. Links private DNS zones to the VNet for name resolution
// 4. Configures network policies to restrict access to private endpoints only
module privateEndpointAndDNS 'modules/security/private-endpoints.bicep' = {
    name: '${uniqueSuffix}-private-endpoint'
    params: {
      aiAccountName: aiAccount.outputs.accountName    // AI Services to secure
      aiSearchName: aiDependencies.outputs.aiSearchName       // AI Search to secure
      storageName: aiDependencies.outputs.azureStorageName        // Storage to secure
      cosmosDBName:aiDependencies.outputs.cosmosDBName
      vnetName: vnet.outputs.virtualNetworkName    // VNet containing subnets
      peSubnetName: vnet.outputs.peSubnetName        // Subnet for private endpoints
      suffix: uniqueSuffix                                    // Unique identifier
      vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
      vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId // Subscription ID for the VNet
      cosmosDBSubscriptionId: cosmosDBSubscriptionId // Subscription ID for Cosmos DB
      cosmosDBResourceGroupName: cosmosDBResourceGroupName // Resource Group for Cosmos DB
      aiSearchSubscriptionId: aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
      aiSearchResourceGroupName: aiSearchServiceResourceGroupName // Resource Group for AI Search Service
      storageAccountResourceGroupName: azureStorageResourceGroupName // Resource Group for Storage Account
      storageAccountSubscriptionId: azureStorageSubscriptionId // Subscription ID for Storage Account
  existingDnsZones: enrichedExistingDnsZones
    }
    dependsOn: [
    aiSearch      // Ensure AI Search exists
    storage       // Ensure Storage exists
    cosmosDB      // Ensure Cosmos DB exists
  ]
  }

/*
  Creates a new project (sub-resource of the AI Services account)
*/
module aiProject 'modules/ai-services/ai-project.bicep' = {
  name: 'ai-${projectName}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    projectName: projectName
    projectDescription: projectDescription
    displayName: displayName
    location: location

    aiSearchName: aiDependencies.outputs.aiSearchName
    aiSearchServiceResourceGroupName: aiDependencies.outputs.aiSearchServiceResourceGroupName
    aiSearchServiceSubscriptionId: aiDependencies.outputs.aiSearchServiceSubscriptionId

    cosmosDBName: aiDependencies.outputs.cosmosDBName
    cosmosDBSubscriptionId: aiDependencies.outputs.cosmosDBSubscriptionId
    cosmosDBResourceGroupName: aiDependencies.outputs.cosmosDBResourceGroupName

    azureStorageName: aiDependencies.outputs.azureStorageName
    azureStorageSubscriptionId: aiDependencies.outputs.azureStorageSubscriptionId
    azureStorageResourceGroupName: aiDependencies.outputs.azureStorageResourceGroupName
    // dependent resources
    accountName: aiAccount.outputs.accountName
  }
  dependsOn: [
     privateEndpointAndDNS
     cosmosDB
     aiSearch
     storage
  ]
}

module formatProjectWorkspaceId 'modules/utilities/format-workspace-id.bicep' = {
  name: 'format-project-workspace-id-${uniqueSuffix}-deployment'
  params: {
    projectWorkspaceId: aiProject.outputs.projectWorkspaceId
  }
}

/*
  Assigns the project SMI the storage blob data contributor role on the storage account
*/
module storageAccountRoleAssignment 'modules/security/storage-account-roles.bicep' = {
  name: 'storage-${azureStorageName}-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: aiDependencies.outputs.azureStorageName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
   storage
   privateEndpointAndDNS
  ]
}

// The Comos DB Operator role must be assigned before the caphost is created
module cosmosAccountRoleAssignments 'modules/security/cosmosdb-account-roles.bicep' = {
  name: 'cosmos-account-ra-${projectName}-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosDBName: aiDependencies.outputs.cosmosDBName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    cosmosDB
    privateEndpointAndDNS
  ]
}

// This role can be assigned before or after the caphost is created
module aiSearchRoleAssignments 'modules/ai-services/ai-search-role-assignments.bicep' = {
  name: 'ai-search-ra-${projectName}-${uniqueSuffix}-deployment'
  scope: resourceGroup(aiSearchServiceSubscriptionId, aiSearchServiceResourceGroupName)
  params: {
    aiSearchName: aiDependencies.outputs.aiSearchName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    aiSearch
    privateEndpointAndDNS
  ]
}

// Create the enterprise_memory database in Cosmos DB before capability host
module cosmosEnterpriseMemoryDatabase 'modules/storage/cosmos-database.bicep' = {
  name: 'cosmos-db-setup-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosAccountName: aiDependencies.outputs.cosmosDBName
    databaseName: 'enterprise_memory'
    throughput: 400
    projectId: aiProject.outputs.projectWorkspaceId
  }
  dependsOn: [
    cosmosDB
    cosmosAccountRoleAssignments
  ]
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules/utilities/capability-host.bicep' = {
  name: 'capabilityHost-configuration-${uniqueSuffix}-deployment'
  params: {
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    projectCapHost: projectCapHost
  }
  dependsOn: [
     aiSearch      // Ensure AI Search exists
     storage       // Ensure Storage exists
     cosmosDB      // Ensure Cosmos DB account exists
     cosmosEnterpriseMemoryDatabase  // Ensure enterprise_memory database and containers exist
     privateEndpointAndDNS
     cosmosAccountRoleAssignments
     storageAccountRoleAssignment
     aiSearchRoleAssignments
  ]
}

// The Storage Blob Data Owner role must be assigned after the caphost is created
module storageContainersRoleAssignment 'modules/security/blob-container-roles.bicep' = {
  name: 'storage-containers-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    aiProjectPrincipalId: aiProject.outputs.projectPrincipalId
    storageName: aiDependencies.outputs.azureStorageName
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  // Role assignments automatically wait for required resources
}

// The Cosmos Built-In Data Contributor role must be assigned after the caphost is created
module cosmosContainerRoleAssignments 'modules/security/cosmos-container-roles.bicep' = {
  name: 'cosmos-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosAccountName: aiDependencies.outputs.cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: aiProject.outputs.projectPrincipalId

  }
  dependsOn: [
    cosmosEnterpriseMemoryDatabase  // Ensure containers are created before role assignments
    storageContainersRoleAssignment
  ]
}// Application Insights and Log Analytics for monitoring
module applicationInsights 'modules/monitoring/application-insights.bicep' = {
  name: 'monitoring-${uniqueSuffix}-deployment'
  params: {
    location: location
    applicationInsightsName: 'appinsights-${uniqueSuffix}'
    logAnalyticsWorkspaceName: 'loganalytics-${uniqueSuffix}'
    vnetName: vnet.outputs.virtualNetworkName
    privateEndpointSubnetName: vnet.outputs.peSubnetName
    suffix: uniqueSuffix
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId
  // Temporarily force disable private endpoints until feature registered
  enablePrivateEndpoints: false
  existingDnsZones: enrichedExistingDnsZones
  }
  dependsOn: [
    privateEndpointAndDNS
  ]
}

// Bing Search for web search capabilities
module bingSearch 'modules/ai-services/bing-search.bicep' = if (enableBingSearch) {
  name: 'bing-search-${uniqueSuffix}-deployment'
  params: {
    bingSearchName: bingSearchName
    vnetName: vnet.outputs.virtualNetworkName
    subnetName: vnet.outputs.peSubnetName
    dnsZoneResourceGroupName: resourceGroup().name
    createDnsZones: true
  }
  dependsOn: [
    privateEndpointAndDNS
  ]
}

// Container App Environment and Registry (but not the Container App itself - AZD manages that)
module containerApp 'modules/aca/container-app.bicep' = {
  name: 'container-app-${uniqueSuffix}-deployment'
  params: {
    location: location
    containerAppEnvironmentName: containerAppEnvironmentName
    containerAppName: containerAppName
  containerRegistryLoginServer: containerRegistry.outputs.containerRegistryLoginServer
  containerRegistryId: containerRegistry.outputs.containerRegistryId
    acaSubnetId: vnet.outputs.acaSubnetId
    vnetName: vnet.outputs.virtualNetworkName
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId
    logAnalyticsWorkspaceId: applicationInsights.outputs.logAnalyticsWorkspaceId
    aiProjectEndpoint: aiProject.outputs.projectWorkspaceId
    applicationInsightsConnectionString: applicationInsights.outputs.applicationInsightsConnectionString
    applicationInsightsInstrumentationKey: applicationInsights.outputs.applicationInsightsInstrumentationKey
    enableBingSearch: enableBingSearch
    bingSearchEndpoint: enableBingSearch ? 'https://api.bing.microsoft.com/' : ''
    bingSearchApiKey: '' // This will be set manually after deployment
  containerAppIngressType: containerAppIngressType
  containerAppEnvironmentInternal: containerAppEnvironmentInternal
  internalAcaDnsZoneCreate: createInternalAcaDnsZone
  internalAcaDnsMode: internalAcaDnsMode
  internalAcaDnsEnabled: internalAcaDnsEnabled
  additionalInternalAcaDnsVnetIds: additionalInternalAcaDnsVnetIds
  internalAcaDnsZoneName: internalAcaDnsZoneName
    tags: azdTags
  createContainerApp: createContainerApp
  }
}

// APIM VNet Peering (optional)
module apimVnetPeering 'modules/networking/vnet-peering.bicep' = if (!empty(apimVnetResourceId)) {
  name: 'apim-vnet-peering-${uniqueSuffix}'
  params: {
    primaryVnetName: vnet.outputs.virtualNetworkName
    primaryVnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    primaryVnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId
    remoteVnetResourceId: apimVnetResourceId
    createPrimaryToRemote: createApimVnetPeering
    createRemoteToPrimary: createApimReversePeering
    allowForwardedTraffic: true
    remoteAllowForwardedTraffic: true
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApp.outputs.containerRegistryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistryName
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerApp.outputs.containerAppEnvironmentId
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppEnvironmentName
output SERVICE_API_IDENTITY_PRINCIPAL_ID string = createContainerApp ? containerApp.outputs.containerAppIdentityPrincipalId : ''
output SERVICE_API_IDENTITY_CLIENT_ID string = createContainerApp ? containerApp.outputs.containerAppIdentityClientId : ''
output SERVICE_API_IDENTITY_ID string = createContainerApp ? containerApp.outputs.containerAppIdentityId : ''
output SERVICE_API_NAME string = createContainerApp ? containerApp.outputs.containerAppName : ''
output SERVICE_API_URI string = createContainerApp ? containerApp.outputs.containerAppUri : ''
output SERVICE_API_ENDPOINTS array = createContainerApp ? [containerApp.outputs.containerAppUri] : []
output RESOURCE_GROUP_ID string = resourceGroup().id
// Internal ACA DNS outputs
output ACA_INTERNAL_DNS_ZONE string = containerApp.outputs.internalAcaDnsZoneName
output ACA_INTERNAL_DNS_FQDN string = containerApp.outputs.internalAcaFqdn

// Internal ACA DNS zone name (only used in explicit mode). Keep empty for auto mode; fill after discovery if switching to explicit.
@description('Internal ACA DNS zone name used when internalAcaDnsMode=explicit (format: internal.<defaultDomain>)')
param internalAcaDnsZoneName string = ''

// AI Services outputs
output AZURE_OPENAI_API_VERSION string = modelVersion
output AZURE_OPENAI_ENDPOINT string = aiAccount.outputs.accountTarget
output AZURE_OPENAI_CHAT_DEPLOYMENT_NAME string = modelName

// Bing Search outputs
output AZURE_BING_SEARCH_ENDPOINT string = enableBingSearch ? 'https://api.bing.microsoft.com/' : ''
output AZURE_BING_SEARCH_API_KEY string = '' // This will be set manually after deployment

// AI Project outputs  
output AZURE_AI_PROJECT_NAME string = projectName
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.projectWorkspaceId
output AZURE_AI_PROJECT_CONNECTION_STRING string = formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid

// Search outputs
output AZURE_SEARCH_ENDPOINT string = 'https://${aiDependencies.outputs.aiSearchName}.search.windows.net'
output AZURE_SEARCH_KEY string = '' // This will be set manually after deployment

// Cosmos DB outputs
output AZURE_COSMOS_ENDPOINT string = 'https://${aiDependencies.outputs.cosmosDBName}.documents.azure.com:443/'
output AZURE_COSMOS_DATABASE_NAME string = cosmosEnterpriseMemoryDatabase.outputs.databaseName
output AZURE_COSMOS_CONTAINER_NAME string = 'memory'

// Storage outputs
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccountName
output AZURE_STORAGE_ACCOUNT_ENDPOINT string = 'https://${aiDependencies.outputs.azureStorageName}.blob.${environment().suffixes.storage}'
output AZURE_STORAGE_CONTAINER_NAME string = 'content'

// Application Insights and monitoring outputs
output APPLICATION_INSIGHTS_CONNECTION_STRING string = applicationInsights.outputs.applicationInsightsConnectionString
output APPLICATION_INSIGHTS_INSTRUMENTATION_KEY string = applicationInsights.outputs.applicationInsightsInstrumentationKey
output LOG_ANALYTICS_WORKSPACE_ID string = applicationInsights.outputs.logAnalyticsWorkspaceId

// Environment variables for Azure Monitor tracing
output ENABLE_AZURE_MONITOR_TRACING bool = true
output AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED bool = true

// Bing Search outputs (conditional)
output BING_SEARCH_ENABLED bool = enableBingSearch
output BING_SEARCH_RESOURCE_NAME string = enableBingSearch ? bingSearchName : ''
output BING_SEARCH_ENDPOINT string = enableBingSearch ? 'https://api.bing.microsoft.com/' : ''
